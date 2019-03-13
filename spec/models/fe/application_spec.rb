require 'rails_helper'

RSpec.describe Fe::Application, :type => :model do
  it { expect have_many :answer_sheet_question_sheets }
  it { expect have_many :question_sheets }
  it { expect have_many :answers }
  it { expect have_many :reference_sheets }

  let(:qs) { create(:question_sheet_with_pages) }
  let(:qs2) { create(:question_sheet_with_pages) }
  let(:p) { qs.pages.first }
  let(:p2) { qs.pages.first }
  let(:ref_el) { create(:reference_element) }
  let(:ref_el2) { create(:reference_element) }
  let(:ref_el3) { create(:reference_element) }
  let(:app) { create(:application) }

  before do
    p.elements << ref_el
    p2.elements << ref_el2
    app.question_sheets << qs << qs2
  end

  context '#percentage_complete' do
    before do
      @q = create(:question_sheet_with_pages)
      @p = @q.pages.first
      @p2 = @q.pages.second

      @yesno = create(:choice_field_element, required: false, label: 'yesno lvl1 hidden-gridparent') # answered
      @grid = create(:question_grid, choice_field: @yesno, label: 'hidden grid')
      @text1 = create(:text_field_element, label: 'lvl2 hidden required', question_grid: @grid, required: true) # NOT answered
      @text2 = create(:text_field_element, label: 'lvl2 hidden required2', question_grid: @grid, required: true) # answered (but doesn't count because hidden)
      @text3 = create(:text_field_element, label: 'lvl2 hidden optional', question_grid: @grid, required: false) # answered (but doesn't count because hidden)
      
      @text4 = create(:text_field_element, label: 'lvl1 optional', required: false) # answered
      @text5 = create(:text_field_element, label: 'lvl1 required', required: true, object_name: 'applicant', attribute_name: 'first_name') # answered
      @text6 = create(:text_field_element, label: 'lvl1 required2', required: true) # NOT answered

      @yesno2 = create(:choice_field_element, required: false, label: 'yesno2 lvl1 visible-gridparent2') # answered
      @grid2 = create(:question_grid, choice_field: @yesno2, label: 'visible grid')
      @text7 = create(:text_field_element, label: 'lvl2 visible required', question_grid: @grid2, required: true) # NOT answered
      @text8 = create(:text_field_element, label: 'lvl2 visible required2', question_grid: @grid2, required: true) # answered
      @text9 = create(:text_field_element, label: 'lvl2 visible optional', question_grid: @grid2, required: false) # answered

      @p.elements << @yesno
      @p.elements << @yesno2
      @p.elements << @text4
      @p.elements << @text5
      @p2.elements << @text6

      person = create(:fe_person)
      @a = create(:application, applicant_id: person.id)

      @yesno.set_response('no', @a)
      @yesno.save_response(@a)
      @yesno2.set_response('yes', @a)
      @yesno2.save_response(@a)
      @text2.set_response('this answer is not counted, yesno parent is no so this is hidden', @a)
      @text2.save_response(@a)
      @text3.set_response('this answer is not counted, yesno parent is no so this is hidden', @a)
      @text3.save_response(@a)
      @text4.set_response('this answer is counted when optional included', @a)
      @text4.save_response(@a)
      @text5.set_response('this answer is counted', @a)
      @text5.save_response(@a)

      @text8.set_response('this answer is counted', @a)
      @text8.save_response(@a)
      @text9.set_response('this answer is counted when optional included', @a)
      @text9.save_response(@a)

      FactoryGirl.create(:answer_sheet_question_sheet, answer_sheet: @a, question_sheet: @q)
    end

    it 'counts only required elements by default' do
      @a.reload
      expect(@a.percent_complete).to eq(50) # 2 of 4
    end
    it 'counts all questions, not just required ones, when specified' do
      @a.reload
      expect(@a.percent_complete(false)).to eq(75) # 6 of 8 (2 yes/no + 3 txts within the 1 visible grid + 2 txts directly on page, 1 on other page)
    end
    it 'supports specifying a page' do
      @a.reload
      expect(@a.percent_complete(false, [@p])).to eq(85) # 6 of 7 (2 yes/no + 3 txts within the 1 visible grid + 2 txts directly on page)
    end
  end

  context '#question_sheets_all_reference_elements' do
    it 'returns all reference elements for all question sheets' do
      expect(app.question_sheets_all_reference_elements).to eq([ref_el, ref_el2])
    end

    it 'returns a reference that was just added' do
      expect(app.question_sheets_all_reference_elements).to eq([ref_el, ref_el2])
      p.elements << ref_el3
      expect(app.question_sheets_all_reference_elements).to eq([ref_el, ref_el2, ref_el3])
    end
  end
end
