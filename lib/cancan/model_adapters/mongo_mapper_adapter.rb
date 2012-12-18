module CanCan
  module ModelAdapters
    class MongoMapperAdapter < AbstractAdapter
      def self.for_class?(model_class)
        model_class <= MongoMapper::Document
      end

      def self.override_conditions_hash_matching?(subject, conditions)
        conditions.any? do |k,v|
          key_is_not_symbol = lambda { !k.kind_of?(Symbol) }
          subject_value_is_array = lambda do
            subject.respond_to?(k) && subject.send(k).is_a?(Array)
          end

          key_is_not_symbol.call || subject_value_is_array.call
        end
      end

      def self.matches_conditions_hash?(subject, conditions)
        subject.class.where(conditions).where(:id => subject.id).exists?
      end

      def base_class
        klass = @model_class
        klass = klass.superclass while klass.single_collection_inherited?
        klass
      end

      def database_records
        # if there are only 'cannot' rules (no 'can' rules), return criteria
        # that won't return any documents
        if @rules.none? {|rule| rule.base_behavior}
          criteria = {:$nor => [{}]}
        else
          criteria = @rules.inject(base_class.where) do |query, rule|
            if rule.base_behavior
              query.where(:$or => [rule.conditions])
            else
              query.where(:$nor => [rule.conditions])
            end
          end.criteria.to_hash
          # criteria with {} in the :$or part can be optimized away
          or_criteria = criteria[:$or] || []
          criteria.delete(:$or) if or_criteria.include?({})
          # a single :$or can be optimized away
          if or_criteria.size == 1
            criteria.delete(:$or)
            criteria.merge! or_criteria.first
          end
          # criteria with {} in the :$nor part can be optimized
          criteria = {:$nor => [{}]} if criteria.include?(:$nor) && criteria[:$nor].include?({})
          # wrap result 'and', so chained criteria won't be merged
          criteria = {:$and => [criteria]} if criteria.any?
        end
        @model_class.where(criteria)
      end
    end
  end
end

module MongoMapper::Document::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
