class Fluent::GrowthForecastOutput < Fluent::Output
  Fluent::Plugin.register_output('growthforecast', self)

  def initialize
    super
    require 'net/http'
    require 'uri'
    require 'resolve/hostname'
  end

  config_param :gfapi_url, :string # growth.forecast.local/api/
  config_param :graph_path, :string, :default => nil
  config_param :service, :string, :default => nil
  config_param :section, :string, :default => nil
  config_param :graphs, :string, :default => nil

  config_param :ssl, :bool, :default => false
  config_param :verify_ssl, :bool, :default => false

  config_param :name_keys, :string, :default => nil
  config_param :name_key_pattern, :string, :default => nil

  config_param :mode, :string, :default => 'gauge' # or count/modified

  config_param :remove_prefix, :string, :default => nil
  config_param :tag_for, :string, :default => 'name_prefix' # or 'ignore' or 'section' or 'service'

  config_param :background_post, :bool, :default => false

  config_param :timeout, :integer, :default => nil # default 60secs
  config_param :retry, :bool, :default => true
  config_param :keepalive, :bool, :default => true
  config_param :enable_float_number, :bool, :default => false

  config_param :authentication, :string, :default => nil # nil or 'none' or 'basic'
  config_param :username, :string, :default => ''
  config_param :password, :string, :default => ''

  DEFAULT_GRAPH_PATH = {
    :ignore => '${service}/${section}/${key_name}',
    :service => '${tag}/${section}/${key_name}',
    :section => '${service}/${tag}/${key_name}',
    :name_prefix => '${service}/${section}/${tag}_${key_name}',
  }

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  def configure(conf)
    super

    if @gfapi_url !~ /\/api\/\Z/
      raise Fluent::ConfigError, "gfapi_url must end with /api/"
    end
    if not @graph_path.nil? and @graph_path !~ /^[^\/]+\/[^\/]+\/[^\/]+$/
      raise Fluent::ConfigError, "graph_path must be like '${service}/${section}/${tag}_${key_name}'"
    end

    if @name_keys.nil? and @name_key_pattern.nil?
      raise Fluent::ConfigError, "missing both of name_keys and name_key_pattern"
    end
    if not @name_keys.nil? and not @name_key_pattern.nil?
      raise Fluent::ConfigError, "cannot specify both of name_keys and name_key_pattern"
    end
    if not @graphs.nil? and @name_keys.nil?
      raise Fluent::ConfigError, "graphs must be specified with name_keys"
    end

    if @name_keys
      @name_keys = @name_keys.split(',').map do |name|
        name.split('.')
      end
    end
    if @name_key_pattern
      @name_key_pattern = Regexp.new(@name_key_pattern)
    end

    if @graphs
      @graphs = @graphs.split(',')
    end
    if @name_keys and @graphs and @name_keys.size != @graphs.size
      raise Fluent::ConfigError, "sizes of name_keys and graphs do not match"
    end

    @mode = case @mode
            when 'count' then :count
            when 'modified' then :modified
            else
              :gauge
            end

    @tag_for = case @tag_for
               when 'ignore' then :ignore
               when 'section' then :section
               when 'service' then :service
               else
                 :name_prefix
               end
    if @graph_path.nil?
      if @tag_for != :section and @section.nil?
        raise Fluent::ConfigError, "section parameter is needed when tag_for is not 'section'"
      end
      if @tag_for != :service and @service.nil?
        raise Fluent::ConfigError, "service parameter is needed when tag_for is not 'service'"
      end
      @graph_path = DEFAULT_GRAPH_PATH[@tag_for]
    end

    if @remove_prefix
      @removed_prefix_string = @remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end

    @auth = case @authentication
            when 'basic' then :basic
            else
              :none
            end
    @resolver = Resolve::Hostname.new(:system_resolver => true)
  end

  def start
    super

    @running = true
    @thread = nil
    @queue = nil
    @mutex = nil
    if @background_post
      @mutex = Mutex.new
      @queue = []
      @thread = Thread.new(&method(:poster))
    end
  end

  def shutdown
    @running = false
    @thread.join if @thread
    super
  end

  def poster
    while @running
      if @queue.size < 1
        sleep(0.2)
        next
      end

      events = @mutex.synchronize {
        es,@queue = @queue,[]
        es
      }
      begin
        post_events(events) if events.size > 0
      rescue => e
        log.warn "HTTP POST in background Error occures to growthforecast server", :error_class => e.class, :error => e.message
      end
    end
  end

  def placeholder_mapping(tag, name)
    if @remove_prefix and
        ( (tag.start_with?(@removed_prefix_string) and tag.length > @removed_length) or tag == @remove_prefix)
      tag = tag[@removed_length..-1]
    end
    {'${service}' => @service, '${section}' => @section, '${tag}' => tag, '${key_name}' => name}
  end

  def format_url(tag, name)
    graph_path = @graph_path.gsub(/(\${[_a-z]+})/, placeholder_mapping(tag, name))
    return @gfapi_url + URI.escape(graph_path)
  end

  def connect_to(tag, name)
    url = URI.parse(format_url(tag,name))
    return url.host, url.port
  end

  def http_connection(host, port)
    http = Net::HTTP.new(@resolver.getaddress(host), port)
    if @timeout
      http.open_timeout = @timeout
      http.read_timeout = @timeout
    end
    if @ssl
      http.use_ssl = true
      unless @verify_ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
    http
  end

  def post_request(tag, name, value)
    url = URI.parse(format_url(tag,name))
    req = Net::HTTP::Post.new(url.path)
    if @auth and @auth == :basic
      req.basic_auth(@username, @password)
    end
    req['Host'] = url.host
    if @keepalive
      req['Connection'] = 'Keep-Alive'
    end
    value = @enable_float_number ? value.to_f : value.to_i
    req.set_form_data({'number' => value, 'mode' => @mode.to_s})
    req
  end

  def post(tag, name, value)
    url = format_url(tag,name)
    res = nil
    begin
      host,port = connect_to(tag, name)
      req = post_request(tag, name, value)
      http = http_connection(host, port)
      res = http.start {|http| http.request(req) }
    rescue IOError, EOFError, SystemCallError
      # server didn't respond
      log.warn "net/http POST raises exception: #{$!.class}, '#{$!.message}'"
    end
    unless res and res.is_a?(Net::HTTPSuccess)
      log.warn "failed to post to growthforecast: #{url}, number: #{value}, code: #{res && res.code}"
    end
  end

  def post_keepalive(events) # [{:tag=>'',:name=>'',:value=>X}]
    return if events.size < 1

    # gf host/port is same for all events (host is from configuration)
    host,port = connect_to(events.first[:tag], events.first[:name])

    requests = events.map{|e| post_request(e[:tag], e[:name], e[:value])}

    http = nil
    requests.each do |req|
      begin
        unless http
          http = http_connection(host, port)
          http.start
        end
        res = http.request(req)
        unless res and res.is_a?(Net::HTTPSuccess)
          log.warn "failed to post to growthforecast: #{host}:#{port}#{req.path}, post_data: #{req.body} code: #{res && res.code}"
        end
      rescue IOError, EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT, SystemCallError
        log.warn "net/http keepalive POST raises exception: #{$!.class}, '#{$!.message}'"
        begin
          http.finish
        rescue => e
          # ignore all errors for connection with error
        end
        http = nil
      end
    end
    begin
      http.finish
    rescue => e
      # ignore
    end
  end

  def post_events(events)
    if @keepalive
      post_keepalive(events)
    else
      events.each do |event|
        post(event[:tag], event[:name], event[:value])
      end
    end
  end

  def emit(tag, es, chain)
    events = []
    if @name_keys
      es.each {|time,record|
        @name_keys.each_with_index {|name, i|
          value = record
          name.each {|k|
            break value = nil if not value.has_key?(k)
            value = value[k]
          }
          if not value.nil?
            events.push({:tag => tag, :name => (@graphs ? @graphs[i] : name.join(".")), :value => value})
          end
        }
      }
    else # for name_key_pattern
      es.each {|time,record|
        record.keys.each {|key|
          if @name_key_pattern.match(key) and record[key]
            events.push({:tag => tag, :name => key, :value => record[key]})
          end
        }
      }
    end
    if @thread
      @mutex.synchronize do
        @queue += events
      end
    else
      begin
        post_events(events)
      rescue => e
        log.warn "HTTP POST Error occures to growthforecast server", :error_class => e.class, :error => e.message
        raise if @retry
      end
    end

    chain.next
  end
end
