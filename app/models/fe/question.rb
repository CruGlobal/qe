# Question
# - An individual question element
# - children: TextField, ChoiceField, DateField, FileField

# :kind         - 'TextField', 'ChoiceField', 'DateField' for single table inheritance (STI)
# :label        - label for the question, such as "First name"
# :style        - essay|phone|email|numeric|currency|simple, selectbox|radio, checkbox, my|mdy
# :required     - is this question itself required or optional?
# :content      - choices (one per line) for choice field

module Fe
  class Question < Element
    include ActionView::RecordIdentifier # dom_id
    has_many :conditions,
             :class_name => "Condition",
             :foreign_key => "toggle_id",
             :dependent => :nullify

    has_many :dependents,
             :class_name => "Condition",
             :foreign_key => "trigger_id",
             :dependent => :nullify

    has_many :sheet_answers,
             :class_name => "Answer",
             :foreign_key => "question_id",
             :dependent => :destroy

    belongs_to :related_question_sheet,
               :class_name => "QuestionSheet",
               :foreign_key => "related_question_sheet_id"

    # validates_inclusion_of :required, :in => [false, true]

    validates_format_of :slug, :with => /\A[a-z_][a-z0-9_]*\z/,
                        :allow_nil => true, :if => Proc.new { |q| !q.slug.blank? },
                        :message => 'may only contain lowercase letters, digits and underscores; and cannot begin with a digit.' # enforcing lowercase because javascript is case-sensitive
    validates_length_of :slug, :in => 4..128,
                        :allow_nil => true, :if => Proc.new { |q| !q.slug.blank? }

    validates_each :slug, allow_nil: true, allow_blank: true do |record, attr, value|
      record.pages_on.collect(&:question_sheet).uniq.each do |qs|
        if qs.all_elements.where(slug: record.slug).where("id != ?", record.id).any?
          record.errors.add(attr, "must be unique (within the question sheet)")
        end
      end
    end

    # a question has one response per AnswerSheet (that is, an instance of a user filling out the question)
    # generally the response is a single answer
    # however, "Choose Many" (checkbox) questions have multiple answers in a single response

    attr_accessor :answers

    # @answers = nil            # one or more answers in response to this question
    # @mark_for_destroy = nil   # when something is unchecked, there are less answers to the question than before


    # a question is disabled if there is a condition, and that condition evaluates to false
    # could set multiple conditions to influence this question, in which case all must be met
    # def active?
    #   # find first condition that doesn't pass (nil if all pass)
    #   self.conditions.find(:all).find { |c| !c.evaluate? }.nil?  # true if all pass
    # end

    # def conditions_attributes=(new_conditions)
    #   conditions.collect(&:destroy)
    #   conditions.reload
    #   (0..(new_conditions.length - 1)).each do |i|
    #     i = i.to_s
    #     expression = new_conditions[i]["expression"]
    #     trigger_id = new_conditions[i]["trigger_id"].to_i
    #     unless expression.blank? || !page.questions.collect(&:id).include?(trigger_id) || conditions.collect(&:trigger_id).include?(trigger_id)
    #       conditions.create(:question_sheet_id => question_sheet_id, :trigger_id => trigger_id,
    #                         :expression => expression, :toggle_page_id => page_id,
    #                         :toggle_id => self.id)
    #     end
    #   end
    # end

    # element view provides the element label with required indicator
    def default_label?
      true
    end

    # NOTE: current_person is passed in for the benefit of enclosing apps that override locked?
    # and need to lock an element depending on who the current person is
    def locked?(params, answer_sheet, presenter, current_person)
      return true unless params['action'] == 'edit'
      if self.object_name == 'person.current_address' && ['address1','address2','city','zip','email','state','country'].include?(self.attribute_name)
        # Billing Address
        return false
      elsif self.object_name == 'person.emergency_address' && ['address1','address2','city','zip','email','state','country','contactName','homePhone','workPhone'].include?(self.attribute_name)
        # Emergency Contact
        return false
      elsif self.label == 'Relationship To You' || self.style == "country" || (self.style == "email" && self.label == "Confirm Email")
        # Relationship & Country & Email Address
        return false
      else
        return answer_sheet.frozen? && !presenter.reference? &&
          !@answer_sheet.try(:reference?)
      end
    end

    # css class names for javascript-based validation
    def validation_class(answer_sheet = nil)
      if required?(answer_sheet)
        ' required '
      else
        ''
      end
    end

    # just in case something slips through client-side validation?
    # def valid_response?
    #   if self.required? && !self.has_response? then
    #     false
    #   else
    #     # other validations
    #     true
    #   end
    # end

    # just in case something slips through client-side validation?
    # def valid_response_for_answer_sheet?(answers)
    #    return true if !self.required?
    #    answer  = answers.detect {|a| a.question_id == self.id}
    #    return answer && answer.value.present?
    #    # raise answer.inspect
    #  end

    # shortcut to return first answer
    def response(answer_sheet)
      responses(answer_sheet).first.to_s
    end

    def display_response(answer_sheet)
      r = responses(answer_sheet)
      if r.blank?
        ""
      else
        r.join(", ")
      end
    end

    def responses(answer_sheet)
      return [] unless answer_sheet

      # try to find answer from external object
      if !object_name.blank? and !attribute_name.blank?
        obj = %w(answer_sheet application reference).include?(object_name) ? answer_sheet : eval("answer_sheet." + object_name)
        if obj.nil? or eval("obj." + attribute_name + ".nil?")
          []
        else
          [eval("obj." + attribute_name)]
        end
      else
        answers = sheet_answers.where(answer_sheet: answer_sheet)
        answers = answers.where("value IS NOT NULL AND value != ''")
        answers.to_a
      end
    end

    # set answers from posted response
    def set_response(values, answer_sheet)
      values = Array.wrap(values)
      if !object_name.blank? and !attribute_name.blank?
        # if eval("answer_sheet." + object_name).present?
        object = %w(answer_sheet application).include?(object_name) ? answer_sheet : eval("answer_sheet." + object_name)
        unless object.present?
          if object_name.include?('.')
            objects = object_name.split('.')
            object = eval("answer_sheet." + objects[0..-2].join('.') + ".create_" + objects.last)
            eval("answer_sheet." + objects[0..-2].join('.')).reload
          end
        end
        unless responses(answer_sheet) == values
          value = values.first
          if self.is_a?(Fe::DateField) && value.present?
            begin
              value = Date.strptime(value, '%Y-%m-%d')
            rescue
              raise "invalid date - " + value.inspect
            end
          end
          object.update_attribute(attribute_name, value)
        end
        # else
        #   raise object_name.inspect + ' == ' + attribute_name.inspect
        # end
      else
        @answers = sheet_answers.where(answer_sheet_id: answer_sheet.id).to_a
        @answer_sheet_answers_are_for = answer_sheet
        @mark_for_destroy ||= []
        # go through existing answers (in reverse order, as we delete)
        (@answers.length - 1).downto(0) do |index|
          # reject: skip over responses that are unchanged
          unless values.reject! {|value| value == @answers[index]}
            # remove any answers that don't match the posted values
            @mark_for_destroy << @answers[index]   # destroy from database later
            @answers.delete_at(index)
          end
        end

        # insert any new answers
        for value in values
          if @mark_for_destroy.empty?
            answer = Fe::Answer.new(:question_id => self.id)
          else
            # re-use marked answers (an update vs. a delete+insert)
            answer = @mark_for_destroy.pop
          end
          answer.set(value)
          @answers << answer
        end
      end
    end

    def check_answer_sheet_matches_set_response_answer_sheet(answer_sheet)
      if @answer_sheet_answers_are_for && @answer_sheet_answers_are_for != answer_sheet
        fail("Trying to save answers to a different answer sheet than the one given in set_response")
      end
    end

    def save_file(answer_sheet, file)
      check_answer_sheet_matches_set_response_answer_sheet(answer_sheet)
      @answers.collect(&:destroy) if @answers
      Fe::Answer.create!(:question_id => self.id, :answer_sheet_id => answer_sheet.id, :attachment => file)
    end

    def delete_file(answer_sheet, answer)
      check_answer_sheet_matches_set_response_answer_sheet(answer_sheet)
      answer.destroy
    end

    # save this question's @answers to database
    def save_response(answer_sheet)
      check_answer_sheet_matches_set_response_answer_sheet(answer_sheet)
      unless @answers.nil?
        for answer in @answers
          if answer.is_a?(Fe::Answer)
            answer.answer_sheet_id = answer_sheet.id
            answer.save!
          end
        end
      end

      # remove others
      unless @mark_for_destroy.nil?
        for answer in @mark_for_destroy
          answer.destroy
        end
        @mark_for_destroy.clear
      end

      # clear hidden elements cache on page since this answer might modify which elements are hidden
      pages_on.each do |p| p.clear_all_hidden_elements; end

    rescue TypeError
      raise answer.inspect
    end

    # has any sort of non-empty response?
    def has_response?(answer_sheet = nil)
      answers = answer_sheet.present? ? responses(answer_sheet) : sheet_answers
      return false if answers.length == 0
      answers.each do |answer|
        value = answer.is_a?(Fe::Answer) ? answer.value : answer
        return true if (value.is_a?(FalseClass) && value === false) || value.present?
      end
      false
    end

  end
end
