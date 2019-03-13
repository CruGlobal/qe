module Fe
  module AnswerSheetConcern
    extend ActiveSupport::Concern

    begin
      included do
        has_many :answer_sheet_question_sheets, foreign_key: 'answer_sheet_id', class_name: '::Fe::AnswerSheetQuestionSheet'
        has_many :question_sheets, through: :answer_sheet_question_sheets, class_name: 'Fe::QuestionSheet'
        has_many :answers, ->(answer_sheet) {
          question_sheet_ids = answer_sheet.question_sheet_ids

          if question_sheet_ids.any?
            element_ids = Fe::Page.joins(:question_sheet).where(question_sheet_id: question_sheet_ids).pluck(:all_element_ids).compact
            element_ids = element_ids.collect{ |e| e.split(',') }.flatten
          end

          unless question_sheet_ids.any? && element_ids.any?
            # an answer sheet not assigned to a question sheet, or assigned to
            # a question sheet with no elements should not return any answers
            return where('false')
          end

          where('question_id' => element_ids)

        }, foreign_key: 'answer_sheet_id', class_name: '::Fe::Answer'
        has_many :reference_sheets, :foreign_key => 'applicant_answer_sheet_id', class_name: 'Fe::ReferenceSheet'
        has_many :payments, :foreign_key => 'application_id', class_name: 'Fe::Payment'
      end
    rescue ActiveSupport::Concern::MultipleIncludedBlocks
    end

    def languages
      return [] unless question_sheets.first

      unless @languages
        @languages = question_sheets.first.languages
        question_sheets[1..-1].each { |qs| @languages &= qs.languages.select(&:present?) }
      end
      @languages
    end

    def complete?
      !completed_at.nil?
    end

    # answers for this sheet, grouped by question id
    def answers_by_question
      @answers_by_question ||= answers.group_by { |answer| answer.question_id }
    end

    # Convenience method if there is only one question sheet in your system
    def question_sheet
      question_sheets.first
    end

    def pages
      Page.where(question_sheet_id: question_sheets.collect(&:id)).visible.order('number')
    end

    def completely_filled_out?
      pages.all? {|p| p.complete?(self)}
    end

    def has_answer_for?(question_id)
      !answers_by_question[question_id].nil?
    end

    def reference?
      false
    end

    def percent_complete(required_only = true, restrict_to_pages = [])
      # build an element to page lookup using page's cached all_element_ids
      # this will make the hidden? calls on element faster because we can pass the page
      # (the page builds a list of hidden elements for quick lookup)
      elements_to_pages = {}
      pages = question_sheets.collect(&:pages).flatten
      pages = pages & restrict_to_pages if restrict_to_pages.present?
      pages.each do |p|
        p.all_element_ids_arr.each do |e_id|
          elements_to_pages[e_id] = p
        end
      end

      # determine which questions should count towards the questions total in the percent calculation
      countable_questions = question_sheets.collect{ |qs| qs.all_elements.questions }.flatten
      countable_questions.select!{ |e| elements_to_pages[e.id] } if restrict_to_pages.present?
      countable_questions.reject!{ |e| e.hidden?(self, elements_to_pages[e.id]) }
      countable_questions.select!{ |e| e.required } if required_only

      # no progress if there are no questions
      num_questions = countable_questions.length
      return 0 if num_questions == 0

      # count questions with answers in Fe::Answer
      answers = self.answers.where("(question_id IN (?) AND value IS NOT NULL) AND (value != '')", countable_questions.collect(&:id))
      answered_question_ids = answers.pluck('distinct(question_id)')

      # need to look for answers for the remaining questions using has_response?
      # so that questions with object_name/attribute_name set are counted
      other_answered_questions = countable_questions.reject{ |e| answered_question_ids.include?(e.id) }
      other_answered_questions.select!{ |e| e.has_response?(self) }

      # count total
      num_answers = answered_question_ids.count + other_answered_questions.count
      [ [ (num_answers.to_f / num_questions.to_f * 100.0).to_i, 100 ].min, 0 ].max
    end

    def collat_title() "" end

    def question_sheet_ids
      question_sheets.collect(&:id)
    end

    def question_sheets_all_reference_elements
      # forms are generally not changed often so caching on the last updated elementd
      # will provide a good balance of speed and cache invalidation
      element_ids = Rails.cache.fetch(question_sheets + ['answer_sheet#answer_sheet_all_reference_elements', Fe::Element.order('updated_at desc, id desc').first]) do
        question_sheets.compact.collect { |q| q.all_elements.reference_kinds.pluck(:id) }.flatten
      end

      Fe::Element.find(element_ids)
    end
  end
end
