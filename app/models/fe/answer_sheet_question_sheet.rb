module Fe
  class AnswerSheetQuestionSheet < ApplicationRecord
    self.table_name = self.table_name.sub('fe_', Fe.table_name_prefix)
    belongs_to :answer_sheet, class_name: Fe.answer_sheet_class
    belongs_to :question_sheet, optional: true, class_name: 'Fe::QuestionSheet'
  end
end
