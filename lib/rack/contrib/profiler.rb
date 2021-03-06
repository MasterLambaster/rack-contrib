require 'ruby-prof'

module Rack
  # Set the profile=process_time query parameter to download a
  # calltree profile of the request.
  #
  # Pass the :printer option to pick a different result format.
  class Profiler
    MODES = %w(
      process_time
      wall_time
      cpu_time
      allocations
      memory
      gc_runs
      gc_time
    )

    RP = ::RubyProf
    DEFAULT_PRINTER = RP::CallTreePrinter

    DEFAULT_CONTENT_TYPE = 'application/octet-stream'
    PRINTER_CONTENT_TYPE = {
      RP::FlatPrinter => 'text/plain',
      RP::GraphPrinter => 'text/plain',
      RP::GraphHtmlPrinter => 'text/html',
      RP::CallStackPrinter => 'text/html'
    }

    # Accepts a :printer => [:call_tree|:graph_html|:graph|:flat] option
    # defaulting to :call_tree.
    def initialize(app, options = {})
      @app = app
      @printer = parse_printer(options[:printer])
      @times = (options[:times] || 1).to_i
    end

    def call(env)
      if mode = profiling?(env)
        profile(env, mode)
      else
        @app.call(env)
      end
    end

    private
      def profiling?(env)
        unless RP.running?
          request = Rack::Request.new(env.clone)
          if mode = request.params.delete('profile')
            if RP.const_defined?(mode.upcase)
              mode
            else
              env['rack.errors'].write "Invalid RubyProf measure_mode: " +
                "#{mode}. Use one of #{MODES.to_a.join(', ')}"
              false
            end
          end
        end
      end

      def profile(env, mode)
        RP.measure_mode = RP.const_get(mode.upcase)

        GC.enable_stats if GC.respond_to?(:enable_stats)
        result = RP.profile do
          @times.times { @app.call(env) }
        end
        GC.disable_stats if GC.respond_to?(:disable_stats)

        [200, headers(@printer, env, mode), print(@printer, result)]
      end

      def print(printer, result)
        body = StringIO.new
        printer.new(result).print(body, :min_percent => 0.01)
        body.rewind
        body
      end

      def headers(printer, env, mode)
        headers = { 'Content-Type' => PRINTER_CONTENT_TYPE[printer] || DEFAULT_CONTENT_TYPE }
        if printer == RP::CallTreePrinter
          filename = ::File.basename(env['PATH_INFO'])
          headers['Content-Disposition'] =
            %(attachment; filename="#{filename}.#{mode}.tree")
        end
        headers
      end

      def parse_printer(printer)
        if printer.nil?
          DEFAULT_PRINTER
        elsif printer.is_a?(Class)
          printer
        else
          name = "#{camel_case(printer)}Printer"
          if RP.const_defined?(name)
            RP.const_get(name)
          else
            DEFAULT_PRINTER
          end
        end
      end

      def camel_case(word)
        word.to_s.gsub(/(?:^|_)(.)/) { $1.upcase }
      end
  end
end
