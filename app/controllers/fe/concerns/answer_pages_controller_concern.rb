module Fe::AnswerPagesControllerConcern
  extend ActiveSupport::Concern

  begin
    included do
      before_action :get_answer_sheet, :only => [:show, :edit, :update, :save_file, :delete_file, :index]
      before_action :set_quiet_reference_email_change, only: :update
      skip_before_action :verify_authenticity_token, only: :save_file
    end
  rescue ActiveSupport::Concern::MultipleIncludedBlocks
  end

  def show
    @presenter = Fe::AnswerPagesPresenter.new(self, @answer_sheet, params[:a], nil, true)
    questions = @presenter.questions_for_page(params[:id])
    questions.set_filter(get_filter)
    @elements = questions.elements
    @page = Fe::Page.find(params[:id]) || Fe::Page.find_by_number(1)
  end

  def edit
    questions = @presenter.questions_for_page(params[:id])
    questions.set_filter(get_filter)
    @elements = questions.elements
    @page = Fe::Page.find(params[:id]) || Fe::Page.find_by_number(1)

    render :partial => 'answer_page', :locals => { :show_first => nil }
  end

  # validate and save captured data for a given page
  # PUT /answer_sheets/1/pages/1
  def update
    @page = Fe::Page.find(params[:id])
    questions = @presenter.all_questions_for_page(params[:id])
    questions.set_filter(get_filter)
    questions.post(answer_params, @answer_sheet)
    questions.save
    Fe::UpdateReferenceSheetVisibilityJob.perform_later(@answer_sheet, questions.questions.collect(&:id))

    @elements = questions.elements

    # Save references

    if params[:reference].present?
      params[:reference].keys.each do |id|
        reference_params = params.fetch(:reference)[id].permit(:relationship, :title, :first_name, :last_name, :phone, :email, :is_staff)

        ref = @answer_sheet.reference_sheets.find(id)
        # if the email address has changed, we have to trash the old reference answers
        ref.attributes = reference_params
        ref.save(:validate => false)
      end
    end
    @presenter.active_page = nil
    @answer_sheet.update(locale: session[:locale])
    set_saved_at_timestamp
    respond_to do |format|
      format.js
      #format.html
    end
  end

  def save_file
    params.permit(:Filedata)
    params.permit(:user_file) # jquery html5 uploader uses user_file; handle both as flash is fallback

    if params[:Filedata] || params[:user_file]
      @page = Fe::Page.find(params[:id])
      @presenter.active_page = @page
      question = Fe::Element.find(params[:question_id])
      answer = Fe::Answer.where(:answer_sheet_id => @answer_sheet.id, :question_id => question.id).first
      question.answers = [answer] if answer

      @answer = question.save_file(@answer_sheet, params[:Filedata] || params[:user_file].first)
      set_saved_at_timestamp

      render action: :update
    else
      respond_to do |format|
        format.js { head :ok }
      end
    end
  end

  def delete_file
    @page = Fe::Page.find(params[:id])
    @presenter.active_page = @page
    question = Fe::Element.find(params[:question_id])
    answer = Fe::Answer.where(:answer_sheet_id => @answer_sheet.id, :question_id => question.id).first
    question.answers = [answer] if answer

    @answer = question.delete_file(@answer_sheet, answer)
    set_saved_at_timestamp

    render action: :update
  end

  protected

  def get_answer_sheet
    @answer_sheet = answer_sheet_type.find(params[:answer_sheet_id])
    @presenter = Fe::AnswerPagesPresenter.new(self, @answer_sheet, params[:a])
  end

  # extending classes can override this to set a questions filter
  # see Fe::QuestionSet#set_filter for more details
  def get_filter
  end

  def answer_sheet_type
    (params[:answer_sheet_type] || Fe.answer_sheet_class || 'AnswerSheet').constantize
  end

  def answer_params
    params.fetch(:answers, {}).permit!
  end

  def set_saved_at_timestamp
    @saved_at_timestamp = [@answer_sheet.updated_at, @answer_sheet.answers.maximum(:updated_at)].compact.max
  end

  def set_quiet_reference_email_change
    @answer_sheet.allow_quiet_reference_email_changes = true if @answer_sheet.is_a?(Fe::ReferenceSheet) && params[:a].present?
  end
end
