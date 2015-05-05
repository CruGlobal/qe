# Element represents a section, question or content element on the question sheet
module Fe
  class Element < ActiveRecord::Base
    self.table_name = self.table_name.sub('fe_', Fe.table_name_prefix)

    belongs_to :question_grid,
               class_name: "Fe::QuestionGrid"

    belongs_to :question_grid_with_total,
               class_name: "Fe::QuestionGridWithTotal",
               foreign_key: "question_grid_id"

    belongs_to :choice_field,
               class_name: "Fe::ChoiceField"

    belongs_to :question_sheet, :foreign_key => "related_question_sheet_id"

    belongs_to :conditional, polymorphic: true

    self.inheritance_column = :kind

    has_many :page_elements, dependent: :destroy
    has_many :pages, through: :page_elements

    scope :active, -> { select("distinct(#{Fe::Element.table_name}.id), #{Fe::Element.table_name}.*").where(Fe::QuestionSheet.table_name + '.archived' => false).joins({:pages => :question_sheet}) }
    scope :questions, -> { where("kind NOT IN('Fe::Paragraph', 'Fe::Section', 'Fe::QuestionGrid', 'Fe::QuestionGridWithTotal')") }

    validates_presence_of :kind
    validates_presence_of :style
    # validates_presence_of :label, :style, :on => :update

    validates_length_of :kind, :maximum => 40, :allow_nil => true
    validates_length_of :style, :maximum => 40, :allow_nil => true
    # validates_length_of :label, :maximum => 255, :allow_nil => true

    before_validation :set_defaults, :on => :create
    before_save :set_conditional_element
    after_save :update_any_previous_conditional_elements
    after_save :update_page_all_element_ids

    # HUMANIZED_ATTRIBUTES = {
    #   :slug => "Variable"
    # }changed.include?('address1')
    #
    # def self.human_attrib_name(attr)
    #   HUMANIZED_ATTRIBUTES[attr.to_sym] || super
    # end

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
    def previous_element(question_sheet)
      page_element = page_elements.joins(page: :question_sheet).where("#{Fe::QuestionSheet.table_name}.id" => question_sheet.id).first
      return unless page_element
      index = page_element.page.elements.index(self)
      if index > 0 && prev_el = page_element.page.elements[index-1]
        return prev_el
      end
    end

    def required?(answer_sheet = nil)
      if answer_sheet && 
        self.question_grid.nil? && 
        (prev_el = previous_element(answer_sheet.question_sheet)) && 
        prev_el.is_a?(Fe::Question) && 
        prev_el.class != Fe::QuestionGrid && 
        prev_el.conditional == self &&
        !prev_el.conditional_match(answer_sheet)

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
        (elements + elements.collect(&:all_elements)).flatten
      else
        []
      end
    end

    def reuseable?
      return false if Fe.never_reuse_elements
      (self.is_a?(Fe::Question) || self.is_a?(Fe::QuestionGrid) || self.is_a?(Fe::QuestionGridWithTotal))
    end

    def conditional_match(answer_sheet)
      displayed_response = display_response(answer_sheet)
      return false unless displayed_response && conditional_answer
      (displayed_response.split(',') & conditional_answer.split(',')).length > 0
    end

    def self.max_label_length
      @@max_label_length ||= Fe::Element.columns.find{ |c| c.name == "label" }.limit
    end

    def set_conditional_element
      case conditional_type
      when "Fe::Element"
        pages.reload.each do |page|
          index = page.elements.index(self)
          if index && index < page.elements.length - 1
            self.conditional_id = page.elements[index+1].id
          end
        end
      end
    end

    def update_any_previous_conditional_elements
      pages.reload.each do |page|
        index = page.elements.index(self)
        if index && index > 0
          prev_el = page.elements[index-1]
          if prev_el.conditional_type == "Fe::Element"
            prev_el.update_attribute(:conditional_id, id)
          end
        end
      end
    end

    def update_page_all_element_ids
      pages.each do |p| p.rebuild_all_element_ids end

      [question_grid, question_grid_with_total].compact.each do |field|
        field.update_page_all_element_ids
      end
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
