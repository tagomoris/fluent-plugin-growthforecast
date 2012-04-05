class Fluent::GrowthForecastOutput < Fluent::Output
  Fluent::Plugin.register_output('growthforecast', self)

  def initialize
    super
    require 'net/http'
    require 'uri'
  end

  config_param :gfapi_url, :string # growth.forecast.local/api/
  config_param :service, :string
  config_param :section, :string, :default => nil

  config_param :name_keys, :string, :default => nil
  config_param :name_key_pattern, :string, :default => nil

  config_param :mode, :string, :default => 'gauge' # or count/modified

  config_param :remove_prefix, :string, :default => nil
  config_param :tag_for, :string, :default => 'name_prefix' # or 'ignore' or 'section'
  
  def configure(conf)
    super

    if @gfapi_url !~ /\/api\/\Z/
      raise Fluent::ConfigError, "gfapi_url must end with /api/"
    end
    @gfurl = @gfapi_url + @service + '/'

    if @name_keys.nil? and @name_key_pattern.nil?
      raise Fluent::ConfigError, "missing both of name_keys and name_key_pattern"
    end
    if not @name_keys.nil? and not @name_key_pattern.nil?
      raise Fluent::ConfigError, "cannot specify both of name_keys and name_key_pattern"
    end
    if @name_keys
      @name_keys = @name_keys.split(',')
    end
    if @name_key_pattern
      @name_key_pattern = Regexp.new(@name_key_pattern)
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
               else
                 :name_prefix
               end
    if @tag_for != :section and @section.nil?
      raise Fluent::ConfigError, "section parameter is needed when tag_for is not 'section'"
    end

    if @remove_prefix
      @removed_prefix_string = @remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end
  end

  def start
    super
  end

  def shutdown
    super
  end

  def format_url(tag, name)
    case @tag_for
    when :ignore
      @gfurl + @section + '/' + name
    when :section
      @gfurl + tag + '/' + name
    when :name_prefix
      @gfurl + @section + '/' + tag + '_' + name
    end
  end

  def post(tag, name, value)
    url = format_url(tag,name)
    begin
      res = Net::HTTP.post_form(URI.parse(url), {'number' => value.to_i, 'mode' => @mode.to_s})
    rescue IOError, EOFError, SystemCallError
      # server didn't respond
      $log.warn "Net::HTTP.post_form raises exception: #{$!.class}, '#{$!.message}'"
      res = nil
    end
    unless res and res.is_a?(Net::HTTPSuccess)
      $log.warn "failed to post to growthforecast: #{url}, number: #{value}, code: #{res && res.code}"
    end
  end

  def emit(tag, es, chain)
    if @remove_prefix and
        ( (tag.start_with?(@removed_prefix_string) and tag.length > @removed_length) or tag == @remove_prefix)
      tag = tag[@removed_length..-1]
    end
    if @name_keys
      es.each {|time,record|
        @name_keys.each {|name|
          if record[name]
            post(tag, name, record[name])
          end
        }
      }
    else # for name_key_pattern
      es.each {|time,record|
        record.keys.each {|key|
          if @name_key_pattern.match(key) and record[key]
            post(tag, key, record[key])
          end
        }
      }
    end
    chain.next
  end
end
