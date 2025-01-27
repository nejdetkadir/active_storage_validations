# frozen_string_literal: true

require_relative 'metadata.rb'

module ActiveStorageValidations
  class AspectRatioValidator < ActiveModel::EachValidator # :nodoc
    AVAILABLE_CHECKS = %i[with].freeze
    PRECISION = 3

    def initialize(options)
      require 'mini_magick' unless defined?(MiniMagick)
      super(options)
    end

    def check_validity!
      return true if AVAILABLE_CHECKS.any? { |argument| options.key?(argument) }
      raise ArgumentError, 'You must pass "aspect_ratio: { with: [] }" option to the validator'
    end

    if Rails.gem_version >= Gem::Version.new('6.0.0')
      def validate_each(record, attribute, _value)
        return true unless record.send(attribute).attached?

        changes = record.attachment_changes[attribute.to_s]
        return true if changes.blank?

        files = Array.wrap(changes.is_a?(ActiveStorage::Attached::Changes::CreateMany) ? changes.attachables : changes.attachable)

        files.each do |file|
          metadata = Metadata.new(file).metadata
          next if is_valid?(record, attribute, metadata)
          break
        end
      end
    else
      # Rails 5
      def validate_each(record, attribute, _value)
        return true unless record.send(attribute).attached?
  
        files = Array.wrap(record.send(attribute))
  
        files.each do |file|
          # Analyze file first if not analyzed to get all required metadata.
          file.analyze; file.reload unless file.analyzed?
          metadata = file.metadata
  
          next if is_valid?(record, attribute, metadata)
          break
        end
      end
    end

    private

    def is_valid?(record, attribute, metadata)
      if metadata[:width].to_i <= 0 || metadata[:height].to_i <= 0
        add_error(record, attribute, options[:message].presence || :image_metadata_missing)
        return false
      end

      case options[:with]
      when :square
        return true if metadata[:width] == metadata[:height]
        add_error(record, attribute, :aspect_ratio_not_square)

      when :portrait
        return true if metadata[:height] > metadata[:width]
        add_error(record, attribute, :aspect_ratio_not_portrait)

      when :landscape
        return true if metadata[:width] > metadata[:height]
        add_error(record, attribute, :aspect_ratio_not_landscape)

      else
        if options[:with].is_a?(Array)
          if options[:with].to_a.map { |ratio| valid_ratio?(ratio, metadata) }.all?(false)
            add_error(record, attribute, :aspect_ratio_is_not_match_any_ratio)
          else
            return true
          end
        else
          add_error(record, attribute, :aspect_ratio_unknown)
        end
      end
      false
    end

    def add_error(record, attribute, type, interpolate = options[:with])
      key = options[:message].presence || type
      return if record.errors.added?(attribute, key)
      record.errors.add(attribute, key, aspect_ratio: interpolate)
    end

    def valid_ratio?(ratio, metadata)
      ratio = ratio.split(':')
      (ratio[0].to_f / ratio[1].to_i).round(PRECISION) == file_aspect_ratio(metadata)
    end

    def file_aspect_ratio(metadata)
      (metadata[:width].to_f / metadata[:height].to_i).round(PRECISION)
    end
  end
end
