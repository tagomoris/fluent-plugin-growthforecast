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
  config_param :name_keys, :string

  config_param :mode, :string, :default => 'gauge' # or count/modified

  config_param :remove_prefix, :string, :default => nil
  config_param :tag_for, :string, :default => 'name_prefix' # or 'ignore' or 'section'
  
  def configure(conf)
    super

    if @gfapi_url !~ /\/api\/\Z/
      raise Fluent::ConfigError, "gfapi_url must end with /api/"
    end
    @gfurl = @gfapi_url + @service + '/'

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
    @name_keys = @name_keys.split(',')
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
    $log.warn "NOW, we are going to post data to growthforecast!!!: " + url
    res = Net::HTTP.post_form(URI.parse(url), {'number' => value, 'mode' => @mode.to_s})
    $log.info "response:" + res.code
    case res
    when Net::HTTPSuccess
      # OK
    else
      $log.warn "failed to post to growthforecast: #{url}, number: #{value}"
    end
  end

  def emit(tag, es, chain)
    if @input_tag_remove_prefix and
        ( (tag.start_with?(@removed_prefix_string) and tag.length > @removed_length) or tag == @input_tag_remove_prefix)
      tag = tag[@removed_length..-1]
    end
    es.each {|time,record|
      @name_keys.each {|name|
        if record[name]
          post(tag, name, record[name])
        end
      }
    }
    chain.next
  end
end
