%w(rubygems
mongrel
atom/service
atom/collection
atom/entry).each { |l| require l }

class AtomPubServer < Mongrel::HttpHandler
  @@auth_locations = %w(REDIRECT_X_HTTP_AUTHORIZATION
    X-HTTP_AUTHORIZATION HTTP_AUTHORIZATION)

  def self.auth=(auth)
    @@auth = auth
  end

  def self.store=(store)
    @@store = store
  end

  def store
    @@store
  end

  def auth
    AtomPubServer.class_variable_defined?(:@@auth) ? @@auth : false
  end

  def process(request, response) 
    if auth && !authenticate(request)
      response.start(401, true) do |header, body|
        header['Status'] = 'Unauthorized'
        header['WWW-Authenticate'] = 'Basic realm="My Atom Collection"'
      end
      return
    end

    case request.params[Mongrel::Const::PATH_INFO]
    when '/'
      service(request, response)
    when '/collection.atom'
      collection(request, response)
    when /^\/(\d+)$/, /^\/([a-z0-9\-_]+)$/
      members(request, response, $1)
    else
      response.start(404, true) {}
    end
  end

  protected
    def service(request, response)
      response.start(405, true) {} unless http_method(request) == :get
      response.start(200) do |header, body|
        header['Content-Type'] = 'application/atomsvc+xml'
        service = Atom::Service.new
        service.workspaces.new.collections << store.collection
        body << service 
      end
    end

    def collection(request, response)
      case http_method(request)
      when :get
        response.start(200) do |headers, body|
          headers['Content-Type'] = 'application/atom+xml'
          body << store.collection
        end
      when :post
        slug = request.params['HTTP_SLUG'] || nil
        operation = store.create(request.body, slug)
        response.start(400, true) {} if operation.malformed?
        response.start(500, true) {} if operation.unsuccessful?
        response.start(201) do |headers, body|
          headers['Content-Type'] = 'application/atom+xml;type=entry'
          headers['Location'] = operation.response[:location]
          body << operation.response[:entry]
        end
      else
        response.start(405) {}
      end
    end

    def members(request, response, identifier)
      case http_method(request) 
      when :get
        operation = store.retrieve(identifier)
        unless operation.successful?
          response.start(410, true) {} if operation.gone?
          response.start(404, true) {} if operation.missing?
          response.start(500) {}
        else
          response.start(200) do |headers, body|
            headers['Content-Type'] = 'application/atom+xml;type=entry'
            body << operation.response
          end
        end
      when :put
        operation = store.update(identifier, request.body)
        unless operation.successful?
          response.start(410, true) {} if operation.gone?
          response.start(404, true) {} if operation.missing?
          response.start(400, true) {} if operation.malformed?
          response.start(500) {}
        else
          response.start(200, true) {}
        end
      when :delete
        operation = store.destroy(identifier)
        unless operation.successful?
          response.start(410, true) {} if operation.gone?
          response.start(404, true) {} if operation.missing?
          response.start(500) {}
        else
          response.start(200) {}
        end
      else
        response.start(405) {}
      end
    end

    def http_method(request)
      request.params[Mongrel::Const::REQUEST_METHOD].downcase.to_sym
    end
    
    def authenticate(request)
       auth == get_auth_data(request.params)
    end

    def get_auth_data(request)
      authdata = nil
      for location in @@auth_locations
        if request.has_key?(location)
          # split based on whitespace, but only split into two pieces
          authdata = request[location].to_s.split(nil, 2)
        end
      end
      if authdata and authdata[0] == 'Basic'
        user, password = Base64.decode64(authdata[1]).split(':')[0..1]
      else
        user, password = ['', '']
      end
      return user, password
    end
end
