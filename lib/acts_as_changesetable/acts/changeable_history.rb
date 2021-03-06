module ActsAsChangesetable
  module ChangeableHistory
    # Upon including this module, call setup.
    def self.included(base)
      base.send(:extend, ClassMethods)
      base.changeable_history_setup
    end
    
    # Returns the associated changeable
    def changeable
      return self.changeable_class.find(self.send(self.changeable_fk)) unless (self.changeable_class.respond_to?(:find_with_deleted))
      self.changeable_class.find_with_deleted(self.send(self.changeable_fk))
    rescue 
      false
    end

    
    # Checks the associated changeable and updates it if needed
    def sync_changeable!
      unless(self.changeable)
        self.changeable_class.new_from_history(self)
      end
      self.changeable.sync_changeable! if(self.changeable and self.changeable.updated_at < self.updated_at)
    end
    
    # Add callback after_find - will hurt performance quite a bit... better way to do it?
    def filter_invalid_changesets
      self.changeset_class.exists?(self.changeset_id)
    end
    module ClassMethods
    
      # Finds all matching histories for a given set of changesets
      def find_by_changesets(list_of_changesets)
        list = []
        list_of_changesets ||= []
        list_of_changesets.each {|c| list = list + self.find_all_by_changeset_id(c)}
        list.flatten
      end
      
      # Turns of Rails' autotimestamping if we want to copy timestamps ourselves
      # Then add a belongs_to for :changeset
      def changeable_history_setup
        unless self.changesetable_options.no_copy_timestamps?
          self.instance_eval {
            def record_timestamps; return false; end;
            def record_timestamps=(arg); return false; end;
          }
        end
        belongs_to :changeset, :class_name => self.changeset_class_name
        after_find :filter_invalid_changesets
      end
      
      # Conditionally creates a new change history item based on the changeable given
      # Use force to ignore the dirty tracking of Rails and just force a new history.
      # (Useful since new objects are not considered dirty)
      def new_from_changeable(changeable, force = false)
        # Create field names from symbols
        my_fields = changeable.changeable_fields.map{|m| m.to_s}
        # Find the intersection of tracked fields and changed fields for item.
        if(force || (my_fields & changeable.changed).size > 0 || changeable.new_record? || changeable.frozen?)
          new_change = self.new
          new_change.send("#{self.changeable_fk}=", changeable.id)
          for field in changeable.changeable_fields
            new_change.send("#{field}=", changeable.send(field))
          end
          unless self.changesetable_options.no_copy_timestamps?
            new_change.updated_at = changeable.updated_at if(changeable.respond_to?(:updated_at) && new_change.respond_to?(:updated_at))
            new_change.created_at = changeable.created_at if(changeable.respond_to?(:created_at) && new_change.respond_to?(:created_at))
          end
          unless self.changesetable_options.no_copy_deleted?
            new_change.deleted_at = changeable.deleted_at if(changeable.respond_to?(:deleted_at) && new_change.respond_to?(:deleted_at))
          end
          new_change.changeset = self.changeset_class.active_changeset
          new_change.save
          new_change
        else
          return false
        end
      end
      
      # Returns the latest history item in the table for the given changeable 
      # (we ask the changeable for the correct foreign key value)
      def get_latest_for(changeable)
        my_id = changeable.id
        self.send("find_by_#{self.changeable_fk}", my_id, {:order => 'updated_at DESC', :limit => 1})
      end
      
      # Returns the change history items in the table for the given changeable 
      # (we ask the changeable for the correct foreign key value)     
      # 
      # Use the number option to :limit the amount of changes returned 
      def get_changes_for(changeable, opts = {})
        limit = opts.delete(:limit)
        my_id = changeable.id
        return self.send("find_all_by_#{self.changeable_fk}", my_id, {:order => 'updated_at'}) unless limit
        self.send("find_all_by_#{self.changeable_fk}", my_id, {:order => 'updated_at', :limit => limit})
      end
    end
  end
end