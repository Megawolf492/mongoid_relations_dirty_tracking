require 'mongoid'
require 'active_support/concern'
require 'active_support/core_ext/module/aliasing'


module Mongoid
  module RelationsDirtyTracking
    extend ActiveSupport::Concern

    included do
      before_save        :store_relations_shadow
    end

    def store_initial
      if self.new_record?
        @initial = {}
      else
        @initial = all_tracked_relations_attributes.deep_dup
      end
    end

    def store_relations_shadow
      @relations_shadow = all_tracked_relations_attributes
    end

    def relation_changes
      sort_hash(@initial, @relations_shadow || all_tracked_relations_attributes)
    end

    def previous_changes
      super.merge relation_changes
    end


    def sort_hash(prev, cur)
      prev ||= {}
      cur ||= {}
      return {} unless prev.respond_to?("count") && cur.respond_to?("count")
      good = {}
      (prev.keys | cur.keys).each do |k|
        next if k.in?(["_id", "updated_at"])
        if prev[k].class == Array || cur[k].class == Array
          good_array = []
          p_count = prev[k].count rescue -1
          c_count = cur[k].count rescue -1
          (p_count > c_count ? p_count : c_count).times do |t|
            r = sort_hash((prev[k][t] rescue {}), (cur[k][t] rescue {}))
            good_array << r if r.count > 0
          end
          good[k] = good_array if good_array.count > 0
          next
        end
        good[k] = [prev[k], cur[k]] if prev[k] != cur[k] && (prev[k].present? || cur[k].present?)
      end
      good["_id"] = prev["_id"] || cur["_id"] if good.count > 0
      good.compact
    end



    def all_tracked_relations_attributes
      good_hash = {}
      self.tracked_relations.each do |rel_name|
        good_hash[rel_name] = tracked_relation_attributes(rel_name)
      end
      good_hash
    end


    def tracked_relation_attributes(rel_name)
      rel_name = rel_name.to_s
      values = nil
      if meta = relations[rel_name]
        values = if meta.relation == Mongoid::Relations::Embedded::One
          [send(rel_name).try(:attributes)].compact
        elsif meta.relation == Mongoid::Relations::Embedded::Many
          send(rel_name).map{|a| a.try(:attributes)}.compact
        elsif meta.relation == Mongoid::Relations::Referenced::One
          [send(rel_name).try(:attributes)].compact
        elsif meta.relation == Mongoid::Relations::Referenced::Many
          send(rel_name).map{|a| a.try(:attributes)}.compact
        elsif meta.relation == Mongoid::Relations::Referenced::ManyToMany
          send(rel_name).map{|a| a.try(:attributes)}.compact
        # elsif meta.relation == Mongoid::Relations::Referenced::In
        #   send(meta.foreign_key) && { "#{meta.foreign_key}" => send(meta.foreign_key)}
        end
      end
      values
    end




    def track_relation?(rel_name)
      rel_name = rel_name.to_s

      ([Mongoid::Relations::Referenced::One, Mongoid::Relations::Referenced::Many, Mongoid::Relations::Referenced::ManyToMany,
       Mongoid::Relations::Referenced::In].include?(relations[rel_name].try(:relation)) && self.respond_to?("#{rel_name}_attributes=")) ||
       [Mongoid::Relations::Embedded::One, Mongoid::Relations::Embedded::Many].include?(relations[rel_name].try(:relation))
    end


    def tracked_relations
      @tracked_relations ||= relations.keys.select {|rel_name| track_relation?(rel_name) }
    end
  end
end
