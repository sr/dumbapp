%w(rubygems
active_record
atom/entry
store).each { |lib| require lib }

module AtomPub
  module Store
    class DbStore < Interface     
      def initialize(options={})
        establish_connection(options['database'])
        initialiaze_collection(options['collection'])
      end
      
      def retrieve(id)
        entry = Entry.find(id) 
        return Result[:gone] if entry && entry.deleted?
        atom = entry.to_atom
        atom.edit_url = URI.join(@collection.base, entry.id.to_s)
        Result.new(:successful, atom.to_s)
      rescue ActiveRecord::RecordNotFound
        Result[:missing]
      end
      
      def create(entry_xml)
        entry = Entry.new
        entry.from_atom(entry_xml)
        if entry.save
          Result.new(:successful, {
            :location => URI.join(@collection.base, entry.id.to_s), 
            :entry => entry.to_s
          }) 
        else
          Result[:unsuccessful]
        end
      rescue Atom::ParseError
        Result[:malformed]
      end
     
      def update(id, entry_xml)
        entry = Entry.find(id)
        entry.from_atom(entry_xml)
        return Result[:gone] if entry.deleted?
        entry.save ? Result[:successful] : Result[:unsuccessful]
      rescue ActiveRecord::RecordNotFound
        Result[:missing]
      rescue Atom::ParseError
        Result[:malformed]
      end

      def destroy(id)
        entry = Entry.find(id)
        return Result[:gone] if entry && entry.deleted?
        return (entry.destroy ? Result[:successful] : Result[:unsuccessful])
      rescue ActiveRecord::RecordNotFound
        Result[:missing]
      end
      
      def collection
        @collection.entries.delete_if { true }
        Entry.find(:all).each do |entry| 
          entry_id = entry.id
          atom_entry = entry.to_atom
          atom_entry.edit_url = URI.join(@collection.base, entry_id.to_s)
          @collection.entries << atom_entry
        end
        @collection
      end

      protected
        def initialiaze_collection(options)
          @collection = Atom::Collection.new( URI.join(options['uri'], 'collection.atom') )
          @collection.base = options['uri']
          @collection.title = options['title']
          
          if options.has_key?('author')
            author = @collection.authors.new
            options['author'].each_key do |property|
              attribute = "#{property}=".to_sym
              author.send(attribute, options['author'][property]) if author.respond_to?(attribute)
            end
          end
        end
    end
  end
end

module Models
  class Entry < ActiveRecord::Base
    def from_atom(xml)
      entry = Atom::Entry.parse(xml)
      self.attributes = {
          :title    => entry.title.to_s, 
          :content  => entry.content.to_s,
          :draft    => !!entry.draft
      } 
    end
    
    def to_atom
      Atom::Entry.new do |e|
        e.title   = title
        e.content = content
        e.updated = updated_at || created_at
        e.edited  = updated_at
        e.draft   = draft
      end
    end

    def to_s
      to_atom.to_s
    end

    def deleted?
      !!deleted
    end
  end
  
  module_function
  
  def establish_connection(configuration)
    ActiveRecord::Base.establish_connection(configuration)
    generate_schema unless Entry.table_exists?
  end
    
  def generate_schema
    ActiveRecord::Schema.define do
      create_table :entries do |t|
        t.string  :title,   :null => false
        t.text    :content, :null => false
        t.boolean :draft,   :default => false
        t.boolean :deleted, :default => false
        t.timestamps
      end
    end
  end
end

AtomPub::Store::DbStore.send(:include, Models)
