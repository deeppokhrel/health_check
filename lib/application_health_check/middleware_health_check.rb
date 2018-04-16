module ApplicationHealthCheck
  class MiddlewareHealthcheck

    def initialize(app)
      @app = app
    end

    def call(env)
      (response_type, middleware_checks, full_stack_checks) = parse_env(env)
      if response_type
        if error_response = (ip_blocked(env) || not_authenticated(env))
          return error_response
        end
        ApplicationHealthCheck.installed_as_middleware = true
        errors = ''
        begin
          # Process the checks to be run from middleware
          errors = ApplicationHealthCheck::Utils.process_checks(middleware_checks, true)
          # Process remaining checks through the full stack if there are any
          unless full_stack_checks.empty?
            return @app.call(env)
          end
        rescue => e
          errors = e.message.blank? ? e.class.to_s : e.message.to_s
        end
        healthy = errors.blank?
        msg = healthy ? ApplicationHealthCheck.success : "health_check failed: #{errors}"
        if response_type == 'xml'
          content_type = 'text/xml'
          msg = { healthy: healthy, message: msg }.to_xml
          error_code = ApplicationHealthCheck.http_status_for_error_object
        elsif response_type == 'json'
          content_type = 'application/json'
          msg = { healthy: healthy, message: msg }.to_json
          error_code = ApplicationHealthCheck.http_status_for_error_object
        else
          content_type = 'text/plain'
          error_code = ApplicationHealthCheck.http_status_for_error_text
        end
        [ (healthy ? 200 : error_code), { 'Content-Type' => content_type }, [msg] ]
      else
        @app.call(env)
      end
    end

    protected

    def parse_env(env)
      uri = env['PATH_INFO']
      if uri =~ /^\/#{Regexp.escape ApplicationHealthCheck.uri}(\/([-_0-9a-zA-Z]*))?(\.(\w*))?$/
        checks = $2.to_s == '' ? ['standard'] : $2.split('_')
        response_type = $4.to_s
        middleware_checks = checks & ApplicationHealthCheck.middleware_checks
        full_stack_checks = (checks - ApplicationHealthCheck.middleware_checks) - ['and']
        [response_type, middleware_checks, full_stack_checks ]
      end
    end

    def ip_blocked(env)
      return false if ApplicationHealthCheck.origin_ip_whitelist.blank?
      req = Rack::Request.new(env)
      unless ApplicationHealthCheck.origin_ip_whitelist.include?(req.ip)
        [ ApplicationHealthCheck.http_status_for_ip_whitelist_error,
          { 'Content-Type' => 'text/plain' },
          [ 'Health check is not allowed for the requesting IP' ]
        ]
      end
    end

    def not_authenticated(env)
      return false unless ApplicationHealthCheck.basic_auth_username && ApplicationHealthCheck.basic_auth_password
      auth = MiddlewareHealthcheck::Request.new(env)
      if auth.provided? && auth.basic? && Rack::Utils.secure_compare(ApplicationHealthCheck.basic_auth_username, auth.username) && Rack::Utils.secure_compare(ApplicationHealthCheck.basic_auth_password, auth.password)
        env['REMOTE_USER'] = auth.username
        return false
      end
      [ 401,
        { 'Content-Type' => 'text/plain', 'WWW-Authenticate' => 'Basic realm="Health Check"' },
        [ ]
      ]
    end

    class Request < Rack::Auth::AbstractRequest
      def basic?
        "basic" == scheme
      end

      def credentials
        @credentials ||= params.unpack("m*").first.split(/:/, 2)
      end

      def username
        credentials.first
      end

      def password
        credentials.last
      end
    end

  end
end
