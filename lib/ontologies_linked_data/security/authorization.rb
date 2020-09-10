require 'set'

module LinkedData
  module Security
    class Authorization
      APIKEYS_FOR_AUTHORIZATION = {}

      def initialize(app = nil)
        @app = app
      end

      ROUTES_THAT_BYPASS_SECURITY = Set.new([
        "/",
        "/documentation",
        "/jsonview/jsonview.css",
        "/jsonview/jsonview.js"
      ])

      def call(env)
        req = Rack::Request.new(env)
        params = req.params
        apikey = find_apikey(env, params)

        unless apikey
          status = 401
          response = {
            status: status,
            error: "You must provide an API Key either using the query-string parameter `apikey` or the `Authorization` header: `Authorization: apikey token=my_apikey`. " + \
              "Your API Key can be obtained by logging in at #{LinkedData.settings.ui_host}/account"
          }
        end

        if status != 401 && !authorized?(apikey, env)
          status = 401
          response = {
            status: status,
            error: "You must provide a valid API Key. " + \
              "Your API Key can be obtained by logging in at #{LinkedData.settings.ui_host}/account"
          }
        end

        if status == 401 && !bypass?(env)
          LinkedData::Serializer.build_response(env, status: status, body: response)
        else
          status, headers, response = @app.call(env)
          apikey_cookie(env, headers, apikey, params)
          [status, headers, response]
        end
      end

      # Skip auth unless security is enabled or for routes we know should be allowed
      def bypass?(env)
        return !LinkedData.settings.enable_security \
          || ROUTES_THAT_BYPASS_SECURITY.include?(env["REQUEST_PATH"]) \
          || env["HTTP_REFERER"] && env["HTTP_REFERER"].start_with?(LinkedData.settings.rest_url_prefix)
      end

      ##
      # Inject a cookie with the API Key if it is present and we're in HTML content type
      def apikey_cookie(env, headers, apikey, params)
        # If we're using HTML, inject the apikey in a cookie (ignores bad accept headers)
        begin
          best = LinkedData::Serializer.best_response_type(env, params)
        rescue LinkedData::Serializer::AcceptHeaderError; end
        if best == LinkedData::MediaTypes::HTML
          Rack::Utils.set_cookie_header!(headers, "ncbo_apikey", {:value => apikey, :path => "/", :expires => Time.now+90*24*60*60})
        end
      end

      def find_apikey(env, params)
        apikey = nil
        header_auth = env["HTTP_AUTHORIZATION"] || env["Authorization"]
        if params["apikey"] && params["userapikey"]
          apikey_authed = authorized?(params["apikey"], env)
          return unless apikey_authed
          apikey = params["userapikey"]
        elsif params["apikey"]
          apikey = params["apikey"]
        elsif apikey.nil? && header_auth
          token = Rack::Utils.parse_query(header_auth.split(" ")[1])
          # Strip spaces from start and end of string
          apikey = token["token"].gsub(/\"/, "")
          # If the user apikey is passed, use that instead
          if token["userapikey"] && !token["userapikey"].empty?
            apikey_authed = authorized?(apikey, env)
            return unless apikey_authed
            apikey = token["userapikey"].gsub(/\"/, "")
          end
        elsif apikey.nil? && env["HTTP_COOKIE"] && env["HTTP_COOKIE"].include?("ncbo_apikey")
          cookie = Rack::Utils.parse_query(env["HTTP_COOKIE"])
          apikey = cookie["ncbo_apikey"] if cookie["ncbo_apikey"]
        end
        apikey
      end

      def authorized?(apikey, env)
        return false if apikey.nil?
        if APIKEYS_FOR_AUTHORIZATION.key?(apikey)
          store_user(APIKEYS_FOR_AUTHORIZATION[apikey], env)
        else
          users = LinkedData::Models::User.where(apikey: apikey).include(LinkedData::Models::User.attributes(:all)).to_a
          return false if users.empty?
          # This will kind-of break if multiple apikeys exist
          # Though it is also kind-of ok since we just want to know if a user with corresponding key exists
          user = users.first
          store_user(user, env)
        end
        return true
      end

      def store_user(user, env)
        Thread.current[:remote_user] = user
        env.update("REMOTE_USER" => user)
      end

    end
  end
end
