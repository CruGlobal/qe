# Element represents a section, question or content element on the question sheet
module Fe
  class Element < ApplicationRecord
    self.table_name = self.table_name.sub('fe_', Fe.table_name_prefix)

    belongs_to :question_grid,
               optional: true, class_name: "Fe::QuestionGrid"

    belongs_to :question_grid_with_total,
               optional: true, class_name: "Fe::QuestionGridWithTotal",
               foreign_key: "question_grid_id"

    belongs_to :choice_field,
               optional: true, class_name: "Fe::ChoiceField"

    has_many :choice_field_children, foreign_key: 'choice_field_id',
      class_name: 'Fe::Element'

    belongs_to :question_sheet, optional: true, :foreign_key => "related_question_sheet_id"

    belongs_to :conditional, optional: true, polymorphic: true

    self.inheritance_column = :kind

    has_many :page_elements, dependent: :destroy
    has_many :pages, through: :page_elements

    scope :active, -> { select("distinct(#{Fe::Element.table_name}.id), #{Fe::Element.table_name}.*").where(Fe::QuestionSheet.table_name + '.archived' => false).joins({:pages => :question_sheet}) }
    scope :questions, -> { where("kind NOT IN('Fe::Paragraph', 'Fe::Section', 'Fe::QuestionGrid', 'Fe::QuestionGridWithTotal')") }
    scope :shared, -> { where(share: true) }
    scope :grid_kinds, -> { where(kind: ['Fe::QuestionGrid', 'Fe::QuestionGridWithTotal']) }
    scope :reference_kinds, -> { where(kind: 'Fe::ReferenceQuestion') }

    validates_presence_of :kind
    validates_presence_of :style
    # validates_presence_of :label, :style, :on => :update

    validates_length_of :kind, :maximum => 40, :allow_nil => true
    validates_length_of :style, :maximum => 40, :allow_nil => true
    # validates_length_of :label, :maximum => 255, :allow_nil => true

    before_validation :set_defaults, :on => :create
    before_save :set_conditional_element
    after_save :update_page_all_element_ids
    after_save :update_any_previous_conditional_elements

    serialize :label_translations, Hash
    serialize :tip_translations, Hash
    serialize :content_translations, Hash

    # HUMANIZED_ATTRIBUTES = {
    #   :slug => "Variable"
    # }changed.include?('address1')
    #
    # def self.human_attrib_name(attr)
    #   HUMANIZED_ATTRIBUTES[attr.to_sym] || super
    # end
    def label(locale = nil)
      label_translations[locale].present? ? label_translations[locale] : self[:label]
    end

    def content(locale = nil)
      content_translations[locale].present? ? content_translations[locale] : self[:content]
    end

    def tooltip(locale = nil)
      tip_translations[locale].present? ? tip_translations[locale] : self[:tooltip]
    end

    # returns all pages this element is on, whether that be directly, through a grid, or as a choice field conditional option
    def pages_on
      all_pages = pages.reload + [question_grid, question_grid_with_total, choice_field].compact.collect(&:pages_on)
      all_pages.flatten.uniq
    end

    def has_response?(answer_sheet = nil)
      false
    end

    def limit(answer_sheet = nil)
      if answer_sheet && object_name.present? && attribute_name.present?
        begin
          unless eval("answer_sheet." + self.object_name + ".nil?")
            klass = eval("answer_sheet." + self.object_name + ".class")
            column = klass.columns_hash[self.attribute_name]
            return column.limit
          end
        rescue
          nil
        end
      end
    end

    # assume each element is on a question sheet only once to make things simpler. if not, just take the first one
    # NOTE: getting the previous_element isn't an expensive operation any more because of the all_elements_id cache
    def previous_element(question_sheet, page = nil)
      return false unless question_sheet
      page ||= pages_on.detect{ |p| p.question_sheet == question_sheet }

      index = page.all_element_ids_arr.index(self.id)
      unless index
        # this can happen for yesno options, since they're rendered as elements but aren't on the page or in a grid
        # but just in case self is an element on the page and the element_ids got out of sync, rebuild the all_element_ids
        # and try again
        page.rebuild_all_element_ids
        index = page.all_element_ids_arr.index(self.id)
      end
      if index && index > 0 && prev_el_id = page.all_element_ids_arr[index-1]
        # occasionally the all_elements_ids_arr can get out of sync here, resulting in no element found
        el = Fe::Element.find_by(id: prev_el_id)
        unless el
          page.rebuild_all_element_ids
          index = page.all_element_ids_arr.index(self.id)
          prev_el_id = page.all_element_ids_arr[index-1]
          el = Fe::Element.find(prev_el_id) # give an error at this point if it's not found
        end

        return el
      end
    end

    # return an array of all elements whose answers or visibility might affect
    # the visibility of this element
    def visibility_affecting_element_ids
      return @visibility_affecting_element_ids if @visibility_affecting_element_ids

      # the form doesn't change much so caching on the last updated element will
      # provide a good balance of speed and cache invalidation
      Rails.cache.fetch([self, 'element#visibility_affecting_element_ids', Fe::Element.order('updated_at desc, id desc').first]) do
        elements = []

        elements << question_grid if question_grid
        elements << choice_field if choice_field
        elements += Fe::Element.where(conditional_type: 'Fe::Element', conditional_id: id)
        element_ids = elements.collect(&:id) +
          elements.collect { |e| e.visibility_affecting_element_ids }.flatten
        element_ids.uniq
      end
    end

    def visibility_affecting_questions
      Fe::Question.where(id: visibility_affecting_element_ids)
    end

    def hidden_by_conditional?(answer_sheet, page)
      return false unless answer_sheet.question_sheets.include?(page.question_sheet)
      prev_el = previous_element(page.question_sheet, page)
      prev_el.is_a?(Fe::Question) &&
        prev_el.conditional == self &&
        !prev_el.conditional_match(answer_sheet)
    end

    def hidden_by_choice_field?(answer_sheet)
      choice_field.present? &&
        choice_field.is_a?(Fe::ChoiceField) &&
        choice_field.is_response_false(answer_sheet)
    end

    # use page if it's passed in, otherwise it will revert to the first page in answer_sheet
    def visible?(answer_sheet = nil, page = nil)
      !hidden?(answer_sheet, page)
    end

    # use page if it's passed in, otherwise it will revert to the first page in answer_sheet
    def hidden?(answer_sheet = nil, page = nil)
      page ||= pages_on.detect{ |p| answer_sheet.question_sheets.include?(p.question_sheet) }
      return true if !page || page.hidden?(answer_sheet)
      return page.all_hidden_elements(answer_sheet).include?(self)
    end

    # use page if it's passed in, otherwise it will revert to the first page in answer_sheet
    def required?(answer_sheet = nil, page = nil)
      if answer_sheet && hidden?(answer_sheet, page)
        return false
      else
        required == true
      end
    end

    def position(page = nil)
      if page
        page_elements.where(:page_id => page.id).first.try(:position)
      else
        self[:position]
      end
    end

    def set_position(position, page = nil)
      if page
        pe = page_elements.where(:page_id => page.id).first
        pe.update_attribute(:position, position) if pe
      else
        self[:position] = position
      end
      position
    end

    def page_id(page = nil)
      if page
        page.id
      else
        pages.first.try(:id)
      end
    end

    def question?
      self.kind_of?(Question)
    end


    # by default the partial for an element matches the class name (override as necessary)
    def ptemplate
      self.class.to_s.underscore
    end

    # copy an item and all it's children
    def duplicate(page, parent = nil)
      new_element = self.class.new(self.attributes.except('id', 'created_at', 'updated_at'))
      case parent.class.to_s
        when "Fe::QuestionGrid", "Fe::QuestionGridWithTotal"
          new_element.question_grid_id = parent.id
        when "Fe::ChoiceField"
          new_element.choice_field_id = parent.id
      end
      new_element.position = parent.elements.maximum(:position).to_i + 1 if parent
      new_element.save!(:validate => false)
      Fe::PageElement.create(:element => new_element, :page => page) unless parent

      # duplicate children
      if respond_to?(:elements) && elements.present?
        elements.each {|e| e.duplicate(page, new_element)}
      end

      new_element
    end

    # include nested elements
    def all_elements
      if respond_to?(:elements)
        elements.reload
        #(elements + elements.collect(&:all_elements)).flatten
        elements.collect{ |el|
          [el, el.all_elements]
        }.flatten
      else
        []
      end
    end

    def reuseable?
      return false if Fe.never_reuse_elements
      (self.is_a?(Fe::Question) || self.is_a?(Fe::QuestionGrid) || self.is_a?(Fe::QuestionGridWithTotal))
    end

    def conditional_answers
      conditional_answer.split(';').collect(&:strip)
    end

    def conditional_match(answer_sheet)
      displayed_response = display_response(answer_sheet)
      return false unless displayed_response && conditional_answer
      conditional_answers.include?(displayed_response)
    end

    def self.max_label_length
      @@max_label_length ||= Fe::Element.columns.find{ |c| c.name == "label" }.limit
    end

    def set_conditional_element
      case conditional_type
      when "Fe::Element"
        pages_on.each do |page|

          if index = page.all_element_ids_arr.index(self.id)
            self.conditional_id = page.all_element_ids_arr[index+1]
          else
            self.conditional_id = nil
          end
        end
      when ""
        # keep conditional_type nil instead of empty to be consistent
        self.conditional_type = nil
      end
    end

    def update_any_previous_conditional_elements
      pages_on.each do |page|
        index = page.all_element_ids_arr.index(self.id)
        if index && index > 0
          prev_el = Fe::Element.find(page.all_element_ids_arr[index-1])
          if prev_el.conditional_type == "Fe::Element"
            prev_el.update_column(:conditional_id, id)
          end
        end
      end
    end

    def update_page_all_element_ids
      [question_grid, question_grid_with_total, choice_field].compact.each do |field|
        field.update_page_all_element_ids
      end

      pages.reload.each do |p| p.rebuild_all_element_ids end
    end

    # matches in an AND method; if requested we can add a second filter method later
    # to match on an OR basis
    def matches_filter(filter)
      filter.all? { |method| self.send(method) }
    end

    def css_classes
      css_class.to_s.split(' ').collect(&:strip)
    end

    protected

    def set_defaults
      if self.content.blank?
        case self.class.to_s
          when "Fe::ChoiceField" then self.content ||= "Choice One\nChoice Two\nChoice Three"
          when "Fe::Paragraph" then self.content ||="Lorem ipsum..."
        end
      end

      if self.style.blank?
        case self.class.to_s
          when 'Fe::TextField' then self.style ||= 'essay'
          when "Fe::DateField" then self.style ||= "date"
          when "Fe::FileField" then self.style ||= "file"
          when "Fe::Paragraph" then self.style ||= "paragraph"
          when "Fe::Section" then self.style ||= "section"
          when "Fe::ChoiceField" then self.style = "checkbox"
          when "Fe::QuestionGrid" then self.style ||= "grid"
          when "Fe::QuestionGridWithTotal" then self.style ||= "grid_with_total"
          when "Fe::SchoolPicker" then self.style ||= "school_picker"
          when "Fe::ProjectPreference" then self.style ||= "project_preference"
          when "Fe::StateChooser" then self.style ||= "state_chooser"
          when "Fe::ReferenceQuestion" then self.style ||= "peer"
          else
            self.style ||= self.class.to_s.underscore
        end
      end
    end
  end
end
