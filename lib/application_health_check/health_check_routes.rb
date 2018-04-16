module ActionDispatch::Routing
  class Mapper

    def health_check_routes(prefix = nil)
      ApplicationHealthCheck::Engine.routes_explicitly_defined = true
      add_health_check_routes(prefix)
    end

    def add_health_check_routes(prefix = nil)
      ApplicationHealthCheck.uri = prefix if prefix
      match "#{ApplicationHealthCheck.uri}(/:checks)(.:format)", :to => 'health_check/health_check#index', via: [:get, :post], :defaults => { :format => 'txt' }
    end

  end
end
