# frozen_string_literal: true

require "pg/histogram/railtie"

module Pg
  module Histogram
    # Construct the relation for a new histogram, execute the PostgreSQL
    # statement, and return the non-empty bins.
    #
    # @param relation [ActiveRecord::Relation] The subquery.
    # @param field [Arel::Attributes::Attribute] The numeric-valued field to be binned.
    # @param bins_count [Integer] The number of bins.
    # @param options [Hash] The options.
    # @option options [Integer] :min  The minimum numeric value (optional; computed if blank).
    # @option options [Integer] :max  The maximum numeric value (optional; computed if blank).
    # @return [Array<Pg::Histogram::Bin>] The bins.
    # @raise [ArgumentError] If database connection adapter is neither PostgreSQL nor PostGIS.
    def self.for(*args)
      Pg::Histogram::Relation.new(*args).bins
    end

    # A bin (viz., bucket) of a histogram.
    #
    # @!attribute [rw] id
    #   @return [Integer] The ID for this bin.
    # @!attribute [rw] size
    #   @return [Integer] The number of elements in this bin.
    # @!attribute [rw] inf
    #   @return [Float] The infimum (lower bound) for this bin.
    # @!attribute [rw] sup
    #   @return [Float] The supremum (upper bound) for this bin.
    # @!attribute [rw] min
    #   @return [Float] The minimum element of this bin.
    # @!attribute [rw] max
    #   @return [Float] The maximum element of this bin.
    class Bin
      include ActiveModel::Attributes
      include ActiveModel::AttributeAssignment

      attribute :id, :integer
      attribute :size, :integer
      attribute :inf, :float
      attribute :sup, :float
      attribute :min, :float
      attribute :max, :float
    end

    # A relation for a histogram.
    #
    # @!attribute [r] relation
    #   @return [ActiveRecord::Relation] The subquery.
    # @!attribute [r] field
    #   @return [Arel::Attributes::Attribute] The numeric-valued field to be binned.
    # @!attribute [r] bins_count
    #   @return [Integer] The number of bins.
    # @!attribute [r] options
    #   @return [Hash] The options.
    class Relation
      # The PostgreSQL statement for a histogram.
      #
      # @return [String]
      SQL_FOR_HISTOGRAM = %q(
        WITH
          "subquery" AS (
            %{sql_for_subquery}
          ),
          "min_max" AS (
            %{sql_for_min_max}
          ),
          "histogram" AS (
            SELECT
              width_bucket(
                "subquery"."numeric_value",
                "min_max"."min_numeric_value",
                "min_max"."max_numeric_value",
                %{bins_count}
              ) AS "bin",
              count("subquery"."numeric_value")::bigint AS "frequency",
              min("subquery"."numeric_value")::numeric AS "min_numeric_value",
              max("subquery"."numeric_value")::numeric AS "max_numeric_value"
            FROM
              "min_max",
              "subquery"
            WHERE
              "subquery"."numeric_value" IS NOT NULL
            GROUP BY
              "bin"
            ORDER BY
              "bin"
          )
        SELECT
          "histogram"."bin" AS "id",
          "histogram"."frequency" AS "size",
          ("min_max"."min_numeric_value" + ((("min_max"."max_numeric_value" - "min_max"."min_numeric_value") / %{bins_count}) * ("histogram"."bin" - 1))) AS "inf",
          ("min_max"."min_numeric_value" + ((("min_max"."max_numeric_value" - "min_max"."min_numeric_value") / %{bins_count}) * "histogram"."bin")) AS "sup",
          "histogram"."min_numeric_value" AS "min",
          "histogram"."max_numeric_value" AS "max"
        FROM
          "histogram",
          "min_max"
      ).gsub(/\s+/, ' ').strip.freeze

      # The PostgreSQL statement for the minimum and maximum values of a histogram.
      #
      # @return [String]
      SQL_FOR_MIN_MAX = %q(
        SELECT
          %{sql_for_min_numeric_value} AS "min_numeric_value",
          %{sql_for_max_numeric_value} AS "max_numeric_value"
      ).gsub(/\s+/, ' ').strip.freeze

      # The PostgreSQL statement for the *computed* minimum and maximum values
      # of a histogram.
      #
      # @return [String]
      SQL_FOR_MIN_MAX_AS_SUBQUERY = %q(
        SELECT
          %{sql_for_min_numeric_value} AS "min_numeric_value",
          %{sql_for_max_numeric_value} AS "max_numeric_value"
        FROM
          "subquery"
        WHERE
          "subquery"."numeric_value" IS NOT NULL
      ).gsub(/\s+/, ' ').strip.freeze

      attr_reader :relation, :field, :bins_count, :options

      # Constructor.
      #
      # @param relation [ActiveRecord::Relation] The subquery.
      # @param field [Arel::Attributes::Attribute] The numeric-valued field to be binned.
      # @param bins_count [Integer] The number of bins.
      # @param options [Hash] The options.
      # @option options [Integer] :min  The minimum numeric value (optional; computed if blank).
      # @option options [Integer] :max  The maximum numeric value (optional; computed if blank).
      # @raise [ArgumentError] If database connection adapter is neither PostgreSQL nor PostGIS.
      def initialize(relation, field, bins_count, options = {})
        raise ArgumentError unless is_valid_adapter?

        @relation = relation
        @field = field
        @bins_count = bins_count
        @options = options
      end

      # Returns the non-empty bins for this histogram.
      #
      # @return [Array<Pg::Histogram::Bin>] The non-empty bins for this histogram.
      def bins
        @bins ||= begin
          rows = ActiveRecord::Base.connection.execute(to_sql)

          rows.collect { |row|
            bin = Pg::Histogram::Bin.new
            bin.assign_attributes(row)
            bin
          }
        end
      end

      # Returns the PostgreSQL statement for this histogram.
      #
      # @return [String] The PostgreSQL statement for this histogram.
      def to_sql
        @sql ||= Kernel.sprintf(SQL_FOR_HISTOGRAM, **{
          bins_count: ActiveRecord::Base.connection.quote(bins_count),
          sql_for_min_max: Kernel.sprintf((options[:min].nil? || options[:max].nil?) ? SQL_FOR_MIN_MAX_AS_SUBQUERY : SQL_FOR_MIN_MAX, **{
            sql_for_max_numeric_value: options[:max].try { |value| ActiveRecord::Base.connection.quote(value) } || 'max("subquery"."numeric_value")',
            sql_for_min_numeric_value: options[:min].try { |value| ActiveRecord::Base.connection.quote(value) } || 'min("subquery"."numeric_value")',
          }),
          sql_for_subquery: relation.select(field.as(ActiveRecord::Base.connection.quote_column_name('numeric_value'))).to_sql,
        })
      end

      private

      # Returns `true` if the database connection adapter is PostgreSQL or
      # PostGIS. Otherwise, returns `false`.
      #
      # @return [Boolean]
      def is_valid_adapter?
        adapter = ActiveRecord::Base.connection.try(:instance_values).try(:[], 'config').try(:[], :adapter).try(:to_s)

        %w(postgis postgresql).include?(adapter)
      end
    end
  end
end
