require 'aasm'

# a visitor applies to a sleeve (application)
class Fe::Application < Fe::AnswerSheet

  self.table_name = "#{Fe.table_name_prefix}applications"

  belongs_to :applicant, optional: true, foreign_key: 'person_id', class_name: "Person"
  has_many :references, :class_name => 'ReferenceSheet', :foreign_key => :applicant_answer_sheet_id, :dependent => :destroy
  has_one :answer_sheet_question_sheet, :foreign_key => "answer_sheet_id"
  has_many :answer_sheet_question_sheets, :foreign_key => 'answer_sheet_id'
  has_many :question_sheets, :through => :answer_sheet_question_sheets

  has_paper_trail on: [:update, :destroy], ignore: [:updated_at]

  alias_method :all_references, :references

  # This will be overridden by the state machine defined in the enclosing app
  def completed?
    raise "completed? should be implemented by the extending class"
  end

  # This will be overridden by the state machine defined in the enclosing app
  def submitted?
    raise "submitted? should be implemented by the extending class"
  end

  def completed_references
    sr = Array.new()
    references.each do |r|
      sr << r if r.completed?
    end
    sr
  end

  def get_reference(question_id)
    reference_sheets.each do |r|
      return r if r.question_id == question_id
    end
    return Fe::ReferenceSheet.new()
  end

  def answer_sheets
    a_sheets = [self]
    references.each do |r|
      a_sheets << r
    end
    a_sheets
  end

  def reference_answer_sheets
    r_sheets = Array.new()
    references.each do |r|
      r_sheets << r
    end
    r_sheets
  end

  def has_references?
    self.references.size > 0
  end

end
