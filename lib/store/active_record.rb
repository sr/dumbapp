require 'rubygems'
require 'active_record'
require 'uuid'
require 'atom/entry'
require 'store'

$: << File.expand_path(File.dirname(__FILE__)) + '/../../vendor'

require 'acts_as_paranoid/init'
require 'acts_as_taggable_on_steroids/init'

module DumbApp
  module Store
    class ActiveRecord < Interface     
      def initialize(options={})
        establish_connection(options['database'])
        initialiaze_collection(options['collection'])
      end
      
      def retrieve(identifier)
        entry = Entry.find_by_identifier(identifier) 
        return Result[:missing] unless entry
        return Result[:gone] if entry.deleted?
        atom = entry.to_atom
        atom.edit_url = URI.join(@collection.base, entry.identifier)
        Result.new(:successful, atom.to_s)
      end
      
      def create(entry_xml, slug=nil)
        entry = Entry.new(:slug => slug)
        entry.from_atom(entry_xml)
        if entry.save
          atom_entry = entry.to_atom
          atom_entry.edit_url = URI.join(@collection.base, entry.identifier)
          Result.new(:successful, {
            :location => atom_entry.edit_url,
            :entry => atom_entry.to_s
          }) 
        else
          Result[:unsuccessful]
        end
      rescue Atom::ParseError
        Result[:malformed]
      end
     
      def update(identifier, entry_xml)
        entry = Entry.find_by_identifier(identifier)
        entry.from_atom(entry_xml)
        return Result[:missing] unless entry
        return Result[:gone] if entry.deleted?
        entry.save ? Result[:successful] : Result[:unsuccessful]
      rescue Atom::ParseError
        Result[:malformed]
      end

      def destroy(identifier)
        entry = Entry.find_by_identifier(identifier)
        return Result[:missing] unless entry
        return Result[:gone] if entry.deleted?
        entry.destroy ? Result[:successful] : Result[:unsuccessful]
      end
      
      def collection
        @collection.feed.entries.delete_if { true }
        Entry.find(:all, :order => 'updated_at DESC').each do |entry|
          atom_entry = entry.to_atom
          atom_entry.edit_url = URI.join(@collection.base, entry.identifier)
          @collection.feed.entries << atom_entry
        end
        @collection
      end

      protected
        def initialiaze_collection(options)
          @collection = Atom::Collection.new( URI.join(options['uri'], 'collection.atom') )
          @collection.base = options['uri']
          @collection.title = options['title']
          
          @collection.feed.authors.new({:name => 'foo'})
          if options.has_key?('author')
            author = @collection.feed.authors.new
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
    acts_as_paranoid
    acts_as_taggable
    
    has_many :links

    validates_uniqueness_of :slug, :allow_nil => true

    def before_create
      self.uuid = UUID.uuid
    end

    def self.find_by_identifier(identifier)
      self.find_with_deleted(:first, :conditions => ['slug = :id OR id = :id',
        {:id => identifier}])
    end

    def from_atom(xml)
      entry = Atom::Entry.parse(xml)
      self.attributes = {
          :title    => entry.title.to_s, 
          :summary  => entry.summary.to_s,
          :content  => entry.content.to_s,
          :draft    => entry.draft
      } 
      entry.links.each { |link| links << Link.new(:href => link['href'], :rel => link['rel']) }
      self.tag_list = entry.categories.map { |category| category['term'] }.join(', ')
    end
    
    def to_atom
      entry = Atom::Entry.new
      entry.title   = title
      entry.id      = 'urn:uuid:' + uuid
      entry.content = content
      entry.content['type'] = 'xhtml'
      if summary
        entry.summary = summary
        entry.summary['type'] = 'html'
      end
      entry.published = created_at
      entry.updated = updated_at || created_at
      entry.edited  = updated_at
      entry.draft   = draft
      links.each { |link| entry.links << Atom::Link.new(:href => link.href, :rel => link.rel) }
      entry.tag_with(tag_list)
      entry
    end

    def to_s
      to_atom.to_s
    end

    def identifier
      (slug || id).to_s
    end
  end

  class Link < ActiveRecord::Base
    belongs_to :entry
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
        t.string  :slug
        t.string  :uuid,    :null => false
        t.text    :content, :null => false
        t.text    :summary
        t.boolean :draft,   :default => false
        t.timestamp :deleted_at
        t.timestamps
      end

      create_table :links do |t|
        t.string :rel
        t.string :href
        t.integer :entry_id
      end

      create_table :tags do |t|
        t.string :name
      end
      
      create_table :taggings do |t|
        t.integer :tag_id
        t.integer :taggable_id
        t.string  :taggable_type      
        t.timestamps
      end
      
      add_index :taggings, :tag_id
      add_index :taggings, [:taggable_id, :taggable_type]      
    end
  end
end

DumbApp::Store::ActiveRecord.send(:include, Models)
