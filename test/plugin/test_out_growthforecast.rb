require 'helper'
require 'fluent/test/driver/output'

class GrowthForecastOutputTest < Test::Unit::TestCase
  # setup/teardown and tests of dummy growthforecast server defined at the end of this class...
  GF_TEST_LISTEN_PORT = 5125

  CONFIG1 = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_keys field1,field2,otherfield
      tag_for   name_prefix
  ]

  CONFIG2 = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      tag_for   ignore
      name_keys field1,field2,otherfield
      mode count
  ]

  CONFIG3 = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      tag_for   section
      remove_prefix test
      name_key_pattern ^(field|key)\\d+$
      mode modified
  ]

  CONFIG4 = %[
      gfapi_url http://127.0.0.1:5125/api/
      section   metrics
      name_keys field1,field2,otherfield
      tag_for   service
      remove_prefix test
  ]

  CONFIG_SPACE = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service x
      section   metrics y
      name_keys field z
      tag_for   ignore
  ]

  CONFIG_NON_KEEPALIVE = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_keys field1,field2,otherfield
      tag_for   name_prefix
      keepalive false
  ]

  CONFIG_THREADING_KEEPALIVE = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_keys field1,field2,otherfield
      tag_for   name_prefix
      background_post true
      keepalive true
      timeout   120
  ]

  CONFIG_THREADING_NON_KEEPALIVE = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_keys field1,field2,otherfield
      tag_for   name_prefix
      background_post true
      keepalive false
  ]

  CONFIG_BAD_GRAPHS = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_keys field1,field2,otherfield
      graphs    graph1,graph2
      tag_for   name_prefix
  ]

  CONFIG_GRAPHS_WITHOUT_NAME_KEYS = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_key_pattern ^(field|key)\\d+$
      graphs    graph1,graph2
      tag_for   name_prefix
  ]

  CONFIG_GRAPHS = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_keys field1,field2,otherfield
      graphs    graph1,graph2,othergraph
      tag_for   name_prefix
  ]

  CONFIG_ENABLE_FLOAT_NUMBER = %[
      gfapi_url http://127.0.0.1:5125/api/
      service   service
      section   metrics
      name_keys field1,field2,otherfield
      tag_for   name_prefix
      enable_float_number true
  ]

  CONFIG_GFAPI_PATH = %[
      gfapi_url  http://127.0.0.1:5125/api/
      graph_path ${tag}/metrics/${tag}_${key_name}
      name_keys  field1,field2,otherfield
      remove_prefix test
  ]

  def create_driver(conf=CONFIG1)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::GrowthForecastOutput).configure(conf)
  end

  def test_configure_and_format_url
    d = create_driver
    assert_equal 'http://127.0.0.1:5125/api/', d.instance.gfapi_url
    assert_equal 'service', d.instance.service
    assert_equal 'metrics', d.instance.section
    assert_equal ['field1', 'field2', 'otherfield'], d.instance.name_keys
    assert_nil d.instance.remove_prefix
    assert_equal :name_prefix, d.instance.tag_for
    assert_equal :gauge, d.instance.mode

    assert_equal 'http://127.0.0.1:5125/api/service/metrics/test.data1_field1', d.instance.format_url('test.data1', 'field1')

    d = create_driver(CONFIG2)
    assert_equal 'http://127.0.0.1:5125/api/', d.instance.gfapi_url
    assert_equal 'service', d.instance.service
    assert_equal 'metrics', d.instance.section
    assert_equal ['field1', 'field2', 'otherfield'], d.instance.name_keys
    assert_nil d.instance.remove_prefix
    assert_equal :ignore, d.instance.tag_for
    assert_equal :count, d.instance.mode

    assert_equal 'http://127.0.0.1:5125/api/service/metrics/field1', d.instance.format_url('test.data1', 'field1')

    d = create_driver(CONFIG3)
    assert_equal 'http://127.0.0.1:5125/api/', d.instance.gfapi_url
    assert_equal 'service', d.instance.service
    assert_nil d.instance.section
    assert_equal Regexp.new('^(field|key)\d+$'), d.instance.name_key_pattern
    assert_equal 'test', d.instance.remove_prefix
    assert_equal :section, d.instance.tag_for
    assert_equal 'test.', d.instance.instance_eval{ @removed_prefix_string }
    assert_equal :modified, d.instance.mode

    assert_equal 'http://127.0.0.1:5125/api/service/data1/field1', d.instance.format_url('test.data1', 'field1')

    assert_raise(Fluent::ConfigError) { d = create_driver(CONFIG_BAD_GRAPHS) }
    assert_raise(Fluent::ConfigError) { d = create_driver(CONFIG_GRAPHS_WITHOUT_NAME_KEYS) }
  end

  # CONFIG1 = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     tag_for   name_prefix
  # ]
  def test_emit_1
    d = create_driver(CONFIG1)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'test.metrics_field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'test.metrics_field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'test.metrics_otherfield', v3rd[:name]
  end

  # CONFIG2 = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     tag_for   ignore
  #     name_keys field1,field2,otherfield
  #     mode count
  # ]
  def test_emit_2
    d = create_driver(CONFIG2)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'count', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'otherfield', v3rd[:name]
  end

  # CONFIG3 = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     tag_for   section
  #     remove_prefix test
  #     name_key_pattern ^(field|key)\\d+$
  #     mode modified
  # ]
  def test_emit_3
    d = create_driver(CONFIG3)
    d.run(default_tag: 'test.metrics') do
      # recent ruby's Hash saves elements order....
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'modified', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'field2', v2nd[:name]

    assert_equal 10, v3rd[:data][:number]
    assert_equal 'field3', v3rd[:name]
  end

  # CONFIG1 = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     tag_for   name_prefix
  # ]
  def test_emit_4_auth
    @auth = true # enable authentication of dummy server

    d = create_driver(CONFIG1)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
      # failed in background, and output warn log
    end

    assert_equal 0, @posted.size
    assert_equal 3, @prohibited

    d = create_driver(CONFIG1 + %[
      authentication basic
      username alice
      password wrong_password
    ])
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
      # failed in background, and output warn log
    end

    assert_equal 0, @posted.size
    assert_equal 6, @prohibited

    d = create_driver(CONFIG1 + %[
      authentication basic
      username alice
      password secret!
    ])
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
      # failed in background, and output warn log
    end

    assert_equal 6, @prohibited
    assert_equal 3, @posted.size
  end

  # CONFIG4 = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     tag_for   service
  #     remove_prefix test
  # ]

  def test_emit_5
    d = create_driver(CONFIG4)
    d.run(default_tag: 'test.service') do
      # recent ruby's Hash saves elements order....
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'otherfield', v3rd[:name]
  end

  # CONFIG_SPACE = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service x
  #     section   metrics y
  #     name_keys field z
  #     tag_for   ignore
  # ]
  def test_with_space_1
    d = create_driver(CONFIG_SPACE)
    d.run(default_tag: 'test.foo') do
      d.feed({ 'field z' => 3 })
    end

    assert_equal 1, @posted.size
    v = @posted[0]

    assert_equal 3, v[:data][:number]
    assert_equal 'gauge', v[:data][:mode]
    assert_nil v[:auth]
    assert_equal 'service x', v[:service]
    assert_equal 'metrics y', v[:section]
    assert_equal 'field z', v[:name]
  end

  # CONFIG_NON_KEEPALIVE = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     tag_for   name_prefix
  #     keepalive false
  # ]
  def test_non_keepalive
    d = create_driver(CONFIG_NON_KEEPALIVE)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'test.metrics_field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'test.metrics_field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'test.metrics_otherfield', v3rd[:name]
  end

  # CONFIG_THREADING_KEEPALIVE = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     tag_for   name_prefix
  #     background_post true
  #     keepalive true
  #     timeout   120
  # ]
  def test_threading
    d = create_driver(CONFIG_THREADING_KEEPALIVE)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
      sleep 0.5 # wait internal posting thread loop
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'test.metrics_field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'test.metrics_field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'test.metrics_otherfield', v3rd[:name]
  end

  # CONFIG_THREADING_NON_KEEPALIVE = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     tag_for   name_prefix
  #     background_post true
  #     keepalive false
  # ]
  def test_threading_non_keepalive
    d = create_driver(CONFIG_THREADING_NON_KEEPALIVE)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
      sleep 0.5 # wait internal posting thread loop
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'test.metrics_field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'test.metrics_field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'test.metrics_otherfield', v3rd[:name]
  end


  # CONFIG_GRAPHS = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     graphs    graph1,graph2,othergraph
  #     tag_for   name_prefix
  # ]
  def test_graphs
    d = create_driver(CONFIG_GRAPHS)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'test.metrics_graph1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'test.metrics_graph2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'test.metrics_othergraph', v3rd[:name]
  end

  # CONFIG_NON_KEEPALIVE = %[
  #     gfapi_url http://127.0.0.1:5125/api/
  #     service   service
  #     section   metrics
  #     name_keys field1,field2,otherfield
  #     tag_for   name_prefix
  #     enable_float_number true
  # ]
  def test_enable_float_number
    @enable_float_number = true # enable float number of dummy server

    d = create_driver(CONFIG_ENABLE_FLOAT_NUMBER)
    d.run(default_tag: 'test.metrics') do
      d.feed({ 'field1' => 50.5, 'field2' => -20.1, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50.5, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'test.metrics_field1', v1st[:name]

    assert_equal (-20.1), v2nd[:data][:number]
    assert_equal 'test.metrics_field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'test.metrics_otherfield', v3rd[:name]
  end

  def test_gfapi_path
    d = create_driver(CONFIG_GFAPI_PATH)
    d.run(default_tag: 'test.service') do
      # recent ruby's Hash saves elements order....
      d.feed({ 'field1' => 50, 'field2' => 20, 'field3' => 10, 'otherfield' => 1 })
    end

    assert_equal 3, @posted.size
    v1st = @posted[0]
    v2nd = @posted[1]
    v3rd = @posted[2]

    assert_equal 50, v1st[:data][:number]
    assert_equal 'gauge', v1st[:data][:mode]
    assert_nil v1st[:auth]
    assert_equal 'service', v1st[:service]
    assert_equal 'metrics', v1st[:section]
    assert_equal 'service_field1', v1st[:name]

    assert_equal 20, v2nd[:data][:number]
    assert_equal 'service_field2', v2nd[:name]

    assert_equal 1, v3rd[:data][:number]
    assert_equal 'service_otherfield', v3rd[:name]
  end

  # setup / teardown for servers
  def setup
    Fluent::Test.setup
    @posted = []
    @prohibited = 0
    @auth = false
    @enable_float_number = false
    @dummy_server_thread = Thread.new do
      srv = if ENV['VERBOSE']
              WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => GF_TEST_LISTEN_PORT})
            else
              logger = WEBrick::Log.new('/dev/null', WEBrick::BasicLog::DEBUG)
              WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1', :Port => GF_TEST_LISTEN_PORT, :Logger => logger, :AccessLog => []})
            end
      begin
        srv.mount_proc('/api') { |req,res| # /api/:service/:section/:name
          unless req.request_method == 'POST'
            res.status = 405
            res.body = 'request method mismatch'
            next
          end
          if @auth and req.header['authorization'][0] == 'Basic YWxpY2U6c2VjcmV0IQ==' # pattern of user='alice' passwd='secret!'
            # ok, authorized
          elsif @auth
            res.status = 403
            @prohibited += 1
            next
          else
            # ok, authorization not required
          end

          req.path =~ /^\/api\/([^\/]*)\/([^\/]*)\/(.*)$/
          service = $1
          section = $2
          graph_name = $3
          post_param = Hash[*(req.body.split('&').map{|kv|kv.split('=')}.flatten)]

          number = @enable_float_number ? post_param['number'].to_f : post_param['number'].to_i
          @posted.push({
              :service => service,
              :section => section,
              :name => graph_name,
              :auth => nil,
              :data => { :number => number, :mode => post_param['mode'] },
            })

          res.status = 200
        }
        srv.mount_proc('/') { |req,res|
          res.status = 200
          res.body = 'running'
        }
        srv.start
      ensure
        srv.shutdown
      end
    end

    # to wait completion of dummy server.start()
    require 'thread'
    cv = ConditionVariable.new
    _watcher = Thread.new {
      connected = false
      while not connected
        begin
          get_content('localhost', GF_TEST_LISTEN_PORT, '/')
          connected = true
        rescue Errno::ECONNREFUSED
          sleep 0.1
        rescue StandardError => e
          p e
          sleep 0.1
        end
      end
      cv.signal
    }
    mutex = Mutex.new
    mutex.synchronize {
      cv.wait(mutex)
    }
  end

  def test_dummy_server
    d = create_driver
    d.instance.gfapi_url =~ /^http:\/\/([.:a-z0-9]+)\//
    server = $1
    host = server.split(':')[0]
    port = server.split(':')[1].to_i
    client = Net::HTTP.start(host, port)

    assert_equal '200', client.request_get('/').code
    assert_equal '200', client.request_post('/api/service/metrics/hoge', 'number=1&mode=gauge').code

    assert_equal 1, @posted.size

    assert_equal 1, @posted[0][:data][:number]
    assert_equal 'gauge', @posted[0][:data][:mode]
    assert_nil @posted[0][:auth]
    assert_equal 'service', @posted[0][:service]
    assert_equal 'metrics', @posted[0][:section]
    assert_equal 'hoge', @posted[0][:name]

    assert_equal '200', client.request_post(URI.escape('/api/service x/metrics/hoge'), 'number=1&mode=gauge').code

    assert_equal 2, @posted.size

    assert_equal 1, @posted[1][:data][:number]
    assert_equal 'gauge', @posted[1][:data][:mode]
    assert_nil @posted[1][:auth]
    assert_equal 'service x', @posted[1][:service]
    assert_equal 'metrics', @posted[1][:section]
    assert_equal 'hoge', @posted[1][:name]

    @auth = true

    assert_equal '403', client.request_post('/api/service/metrics/pos', 'number=30&mode=gauge').code

    req_with_auth = lambda do |number, mode, user, pass|
      url = URI.parse("http://#{host}:#{port}/api/service/metrics/pos")
      req = Net::HTTP::Post.new(url.path)
      req.basic_auth user, pass
      req.set_form_data({'number'=>number, 'mode'=>mode})
      req
    end

    assert_equal '403', client.request(req_with_auth.call(500, 'count', 'alice', 'wrong password!')).code

    assert_equal '403', client.request(req_with_auth.call(500, 'count', 'alice', 'wrong password!')).code

    assert_equal 2, @posted.size

    assert_equal '200', client.request(req_with_auth.call(500, 'count', 'alice', 'secret!')).code

    assert_equal 3, @posted.size

  end

  def teardown
    @dummy_server_thread.kill
    @dummy_server_thread.join
  end

end
