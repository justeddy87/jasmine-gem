require 'rack'

module Jasmine
  class RunAdapter
    def initialize(config)
      @config = config
      @jasmine_files = [
        "/__JASMINE_ROOT__/lib/" + File.basename(Dir.glob("#{Jasmine.root}/lib/jasmine*.js").first),
        "/__JASMINE_ROOT__/lib/TrivialReporter.js",
        "/__JASMINE_ROOT__/lib/json2.js",
        "/__JASMINE_ROOT__/lib/consolex.js",
      ]
      @jasmine_stylesheets = ["/__JASMINE_ROOT__/lib/jasmine.css"]
    end

    def call(env)
      return not_found if env["PATH_INFO"] != "/"
      return [200, { 'Content-Type' => 'text/html' }, ''] if (env['REQUEST_METHOD'] == 'HEAD')
      run if env['REQUEST_METHOD'] == 'GET'
    end

    def not_found
      body = "File not found: #{@path_info}\n"
      [404, {"Content-Type" => "text/plain",
             "Content-Length" => body.size.to_s,
             "X-Cascade" => "pass"},
       [body]]
    end

    #noinspection RubyUnusedLocalVariable
    def run(focused_suite = nil)
      jasmine_files = @jasmine_files
      css_files = @jasmine_stylesheets + (@config.css_files || [])
      js_files = @config.js_files(focused_suite)
      body = ERB.new(File.read(File.join(File.dirname(__FILE__), "run.html.erb"))).result(binding)
      [
        200,
        { 'Content-Type' => 'text/html' },
        body
      ]
    end
  end

  class Redirect
    def initialize(url)
      @url = url
    end

    def call(env)
      [
        302,
        { 'Location' => @url },
        []
      ]
    end
  end

  class JsAlert
    def call(env)
      [
        200,
        { 'Content-Type' => 'application/javascript' },
        "document.write('<p>Couldn\\'t load #{env["PATH_INFO"]}!</p>');"
      ]
    end
  end

  class FocusedSuite
    def initialize(config)
      @config = config
    end

    def call(env)
      run_adapter = Jasmine::RunAdapter.new(@config)
      run_adapter.run(env["PATH_INFO"])
    end
  end

  class Server < Rack::Server
    def initialize(config, options = {})
      @config = config
      super(options)
    end

    def app
      @app ||= begin
        thin_config = {
          '/__suite__/' => Jasmine::FocusedSuite.new(@config),
          '/run.html' => Jasmine::Redirect.new('/'),
          '/' => Jasmine::RunAdapter.new(@config)
        }

        @config.mappings.each do |from, to|
          thin_config[from] = Rack::File.new(to)
        end

        thin_config["/__JASMINE_ROOT__"] = Rack::File.new(Jasmine.root)

        Rack::Cascade.new([
          Rack::URLMap.new({'/' => Rack::File.new(@config.src_dir)}),
          Rack::URLMap.new(thin_config)
        ])
      end
    end

    def stop
      server.stop
    end
  end
end
