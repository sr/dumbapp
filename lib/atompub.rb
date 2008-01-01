%w(rubygems
mongrel
atom/service
atom/collection
atom/entry
db_store).each { |l| require l }

class AtomPubServer < Mongrel::HttpHandler
  def self.store=(store)
    @@store = store
  end

  def store
    @@store
  end

  def process(request, response) 
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

  private
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
end
