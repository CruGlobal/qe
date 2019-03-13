require 'acts_as_list'
module Fe
  class Page < ActiveRecord::Base
    self.table_name = self.table_name.sub('fe_', Fe.table_name_prefix)

    belongs_to :question_sheet

    has_many :page_elements, -> { order(:position) },
             dependent: :destroy

    has_many :elements, -> { order(Fe::PageElement.table_name + '.position') },
             through: :page_elements

    has_many :question_grid_with_totals, -> { where("kind = 'Fe::QuestionGridWithTotal'") },
             through: :page_elements,
             source: :element

    has_many :questions, -> { questions.order(Fe::PageElement.table_name + '.position') },
             through: :page_elements,
             source: :element

    has_many :question_grids, -> { where("kind = 'Fe::QuestionGrid'") },
             through: :page_elements,
             source: :element

    # has_many :conditions, :class_name => "Condition", :foreign_key => "toggle_page_id",   # conditions associated with page as a whole
    #         conditions: 'toggle_id is NULL', :dependent => :nullify

    acts_as_list :column => :number, :scope => :question_sheet_id

    scope :visible, -> { where(:hidden => false) }

    # callbacks
    before_validation :set_default_label, :on => :create    # Page x

    # validation
    validates_presence_of :label, :number
    validates_length_of :label, :maximum => 100, :allow_nil => true

    # validates_uniqueness_of :number, :scope => :question_sheet_id

    validates_numericality_of :number, :only_integer => true

    serialize :label_translations, Hash

    # a page is disabled if there is a condition, and that condition evaluates to false
    # could set multiple conditions to influence this question, in which case all must be met
    # def active?
    #   # find first condition that doesn't pass (nil if all pass)
    #   self.conditions.detect { |c| !c.evaluate? }.nil?  # true if all pass
    # end
    #
    # def question?
    #   false
    # end

    def label(locale = nil)
      label_translations[locale] || self[:label]
    end

    # returns true if there is a question element on the page, including one inside a grid
    def has_questions?
      all_questions.any?
    end

    def all_questions
      all_elements.questions
    end

    def questions_before_position(position)
      self.elements.where(["#{Fe::PageElement.table_name}.position < ?", position])
    end

    # Include nested elements
    def all_elements
      ids = all_element_ids_arr
      order = ids.collect{ |id| "id=#{id} DESC" }.join(', ')
      ids.present? ? Element.where(id: ids).order(order) : Element.where("1 = 0")
    end

    def all_element_ids
      rebuild_all_element_ids if self[:all_element_ids].nil?
      self[:all_element_ids]
    end

    def all_element_ids_arr
      @all_element_ids_arr ||= all_element_ids.split(',').collect(&:to_i)
    end

    def rebuild_all_element_ids
      self.update_column :all_element_ids, elements.collect{ |e| [e] + e.all_elements }.flatten.collect(&:id).join(',')
    end

    def copy_to(question_sheet)
      new_page = Fe::Page.new(self.attributes.merge(id: nil))
      new_page.question_sheet_id = question_sheet.id
      new_page.save(:validate => false)
      self.elements.each do |element|
        if !question_sheet.archived? && element.reuseable?
          Fe::PageElement.create(:element => element, :page => new_page)
        else
          element.duplicate(new_page)
        end
      end
      new_page.rebuild_all_element_ids
      new_page
    end

    def hidden?(answer_sheet)
      return true if hidden

      @hidden_cache ||= {}
      return @hidden_cache[answer_sheet] if !@hidden_cache[answer_sheet].nil?

      unless question_sheet.all_elements.where(conditional_type: 'Fe::Page', conditional_id: self).any?
        @hidden_cache[answer_sheet] = false
        return false
      end

      # if any of the conditional questions matches, it's visible
      r = !question_sheet.all_elements.where(conditional_type: 'Fe::Page', conditional_id: self).any?{ |e|
        e.visible?(answer_sheet) && e.conditional_match(answer_sheet)
      }
      @hidden_cache[answer_sheet] = r
      return r
    end

    def clear_hidden_cache
      @hidden_cache = nil
    end

    def complete?(answer_sheet)
      return true if hidden?(answer_sheet)

      all_elements.all? {|e|
        e.hidden?(answer_sheet, self) || !e.required?(answer_sheet, self) || e.has_response?(answer_sheet)
      }
    end

    def started?(answer_sheet)
      all_questions.any? {|e| e.has_response?(answer_sheet)}
    end

    def all_hidden_elements(answer_sheet)
      @all_hidden_elements ||= {}
      @all_hidden_elements[answer_sheet.cache_key] ||= build_all_hidden_elements(answer_sheet)
    end

    def build_all_hidden_elements(answer_sheet)
      @all_hidden_elements ||= {}
      @all_hidden_elements[answer_sheet.cache_key] = []
      all_elements.each do |e|
        next if @all_hidden_elements[answer_sheet.cache_key].include?(e)
        if e.hidden_by_choice_field?(answer_sheet) || e.hidden_by_conditional?(answer_sheet, self)
          @all_hidden_elements[answer_sheet.cache_key] += ([e] + e.all_elements)
          @all_hidden_elements[answer_sheet.cache_key].uniq!
        end
      end
      @all_hidden_elements[answer_sheet.cache_key]
    end

    def clear_all_hidden_elements
      @all_hidden_elements = nil
    end

    private

    # next unused label with "Page" prefix
    def set_default_label
      self.label = Fe.next_label("Page", Fe::Page.untitled_labels(self.question_sheet)) if self.label.blank?
    end

    def self.untitled_labels(sheet)
      sheet ? sheet.pages.where("label like 'Page %'").map {|p| p.label} : []
    end
  end
end
