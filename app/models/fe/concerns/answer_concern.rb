module Fe
  module AnswerConcern
    extend ActiveSupport::Concern
    include ActionView::Helpers::TextHelper

    begin
      included do

        belongs_to :answer_sheet, optional: true
        belongs_to :question, optional: true, :class_name => "Element", :foreign_key => "question_id"

        before_save :set_value_from_filename
      end
    rescue ActiveSupport::Concern::MultipleIncludedBlocks
    end

    def set(value)
      self.value = value
    end

    def to_s
      self.value
    end

    def set_value_from_filename
      self.value = self.attachment_file_name if self[:attachment_file_name].present?
    end

    module ClassMethods
      def table_name
        "#{Fe.table_name_prefix}answers"
      end
    end
  end
end
