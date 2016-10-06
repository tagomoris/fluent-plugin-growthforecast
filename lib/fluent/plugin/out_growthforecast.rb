require 'net/http'
require 'uri'
require 'cgi/util'
require 'resolve/hostname'

class Fluent::Plugin::GrowthForecastOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('growthforecast', self)

  def initialize
    super
  end

  config_param :gfapi_url, :string, # growth.forecast.local/api/
               desc: 'The URL of a GrowthForecast API endpoint.'
  config_param :graph_path, :string, default: nil,
               desc: <<-DESC
The graph path for GrowthForecast API endpoint with the order of service, section, graph_name.
DESC
  config_param :service, :string, default: nil,
               desc: 'The service_name of graphs to create.'
  config_param :section, :string, default: nil,
               desc: 'The section_name of graphs to create.'
  config_param :graphs, :string, default: nil,
               desc: <<-DESC
You may use this option to specify graph names correspond to each of name_keys.
Separate by , (comma). The number of graph names must be same with the number of name_keys.
DESC

  config_param :ssl, :bool, default: false,
               desc: 'Use SSL (https) or not.'
  config_param :verify_ssl, :bool, default: false,
               desc: 'Do SSL verification or not.'

  config_param :name_keys, :string, default: nil,
               desc: <<-DESC
Specify field names of the input record. Separate by , (comma).
The values of these fields are posted as numbers, and names of thease fields are used as parts of grame_names.
Either of name_keys or name_key_pattern is required.
DESC
  config_param :name_key_pattern, :string, default: nil,
               desc: <<-DESC
Specify the field names of the input record by a regular expression.
The values of these fields are posted as numbers,
and names of thease fields are used as parts of grame_names.
Either of name_keys or name_key_pattern is required.
DESC

  config_param :mode, :string, default: 'gauge', # or count/modified
               desc: <<-DESC
The graph mode (either of gauge, count, or modified).
Just same as mode of GrowthForecast POST parameter.
DESC

  config_param :remove_prefix, :string, default: nil,
               desc: 'The prefix string which will be removed from the tag.'
  config_param :tag_for, :string, default: 'name_prefix', # or 'ignore' or 'section' or 'service'
               desc: 'Either of name_prefix, section, service, or ignore.'

  config_param :background_post, :bool, default: false,
               desc: 'Post to GrowthForecast in background thread, without retries for failures'

  config_param :timeout, :integer, default: nil, # default 60secs
               desc: 'Read/Write timeout seconds'
  config_param :retry, :bool, default: true,
               desc: <<-DESC
Do retry for HTTP request failures, or not.
This feature will be set as false for background_post yes automatically.
DESC
  config_param :keepalive, :bool, default: true,
               desc: 'Use a keepalive HTTP connection.'
  config_param :enable_float_number, :bool, default: false,
               desc: 'Post a floating number rather than an interger number.'

  config_param :authentication, :string, default: nil, # nil or 'none' or 'basic'
               desc: 'Specify basic if your GrowthForecast protected with basic authentication.'
  config_param :username, :string, default: '',
               desc: 'The username for authentication.'
  config_param :password, :string, default: '', secret: true,
               desc: 'The password for authentication.'

  DEFAULT_GRAPH_PATH = {
    ignore: '${service}/${section}/${key_name}',
    service: '${tag}/${section}/${key_name}',
    section: '${service}/${tag}/${key_name}',
    name_prefix: '${service}/${section}/${tag}_${key_name}',
  }

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
      @name_keys = @name_keys.split(',')
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
    @resolver = Resolve::Hostname.new(system_resolver: true)
  end

  def prefer_buffered_processing
    @background_post
  end

  def start
    super
  end

  def shutdown
    super
  end

  def placeholder_mapping(tag, name)
    if @remove_prefix and
        ( (tag.start_with?(@removed_prefix_string) and tag.length > @removed_length) or tag == @remove_prefix)
      tag = tag[@removed_length..-1]
    end
    {'${service}' => escape(@service), '${section}' => escape(@section), '${tag}' => escape(tag), '${key_name}' => escape(name)}
  end

  def escape(param)
    escaped ||= param
    escaped = CGI.escape(param) if param
  end

  def format_url(tag, name)
    graph_path = @graph_path.gsub(/(\${[_a-z]+})/, placeholder_mapping(tag, name))
    return @gfapi_url + graph_path
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
        log.warn "net/http keepalive POST raises exception", error: $!
        http.finish rescue nil # ignore all errors for connection with error
        http = nil
      end
    end
    if http
      http.finish rescue nil
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

  def gf_events(tag, time, record)
    events = []
    if @name_keys
      @name_keys.each_with_index do |name, i|
        if value = record[name]
          events.push({tag: tag, name: (@graphs ? @graphs[i] : name), value: value})
        end
      end
    else # for name_key_pattern
      record.keys.each do |key|
        if @name_key_pattern.match(key) and record[key]
          events.push({tag: tag, name: key, value: record[key]})
        end
      end
    end
    events
  end

  def gf_events_from_es(tag, es)
    events = []
    es.each do |time, record|
      events.concat(gf_events(tag, time, record))
    end
    events
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def process(tag, es)
    events = gf_events_from_es(tag, es)
    begin
      post_events(events)
    rescue => e
      log.warn "HTTP POST Error occurs to growthforecast server, ignored (use background_post for retries)", error: e
    end
  end

  def write(chunk)
    events = []
    chunk.msgpack_each do |tag, time, record|
      events << gf_events(tag, time, record)
    end
    begin
      post_events(events.first) # should pass [...] instead of [[...]]
    rescue => e
      log.warn "HTTP POST Error occures to growthforecast server", error: e
      raise if @retry
    end
  end
end
