module DumbApp
  module Store
    class Interface < Object
      def create(entry_xml)
        raise NotImplementedError
      end

      def retrieve(id)
        raise NotImplementedError
      end

      def update(id)
        raise NotImplementedError
      end
        
      def destroy(id)
        raise NotImplementedError
      end
      
      def collection
        raise NotImplementedError
      end
    end

    # Stolen from open_id_authentication rails plugin
    class Result
      attr_reader :response    
      
      ERROR_MESSAGES = {
        :missing    => "Sorry but the entry you requested cannot be found",
        :gone       => "Sorry but the entry has been deleted and is no long accessible",
        :malformed  => "Sorry the entry you provided is malformed"
      }
      
      def self.[](code)
        new(code)
      end
      
      def initialize(code, response=nil)
        @code = code
        @response = response unless response.nil?
      end
      
      def ===(code)
        if code == :unsuccessful && unsuccessful?
          true
        else
          @code == code
        end
      end
      
      ERROR_MESSAGES.keys.each { |state| define_method("#{state}?") { @code == state } }

      def successful?
        @code == :successful
      end

      def unsuccessful?
        ERROR_MESSAGES.keys.include?(@code) || @code == :unsuccessful
      end
      
      def message
        ERROR_MESSAGES[@code]
      end
    end
  end
end
