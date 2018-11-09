require 'validates_email_format_of'
require 'aasm'
module Fe
  class ReferenceSheet < ApplicationRecord
    include Fe::AnswerSheetConcern
    include Rails.application.routes.url_helpers
    include AASM
    include AccessKeyGenerator

    attr_accessor :allow_quiet_reference_email_changes

    self.table_name = "#{Fe.table_name_prefix}references"
    self.inheritance_column = 'fake'

    scope :visible, -> { where(visible: true) }

    belongs_to :question,
               :class_name => 'Fe::ReferenceQuestion',
               :foreign_key => 'question_id'

    belongs_to :applicant_answer_sheet,
               :class_name => "::#{Fe.answer_sheet_class}",
               :foreign_key => "applicant_answer_sheet_id"

    # using belongs_to :question_sheet doesn't work, it uses the Fe::AnswerSheetConcern#question_sheet implementation
    belongs_to :question_sheet_ref, optional: true, class_name: 'Fe::QuestionSheet', foreign_key: :question_sheet_id

    validates_presence_of :first_name, :last_name, :phone, :email, :relationship, :on => :update, :message => "can't be blank"
    validates :email, :email_format => { :on => :update, :message => "doesn't look right." }

    delegate :style, :to => :question

    before_save :reset_reference, if: :new_reference_requested?
    after_save :notify_old_reference_not_needed, if: :new_reference_requested?
    before_create :set_question_sheet
    after_destroy :notify_reference_of_deletion
    after_create :update_visible

    aasm :column => :status do

      state :started, :enter => Proc.new {|ref|
        ref.started_at = Time.now
      }
      state :created, initial: true
      state :completed, :enter => Proc.new {|ref|
        ref.submitted_at = Time.now
        # SpReferenceMailer.deliver_completed(ref)
=begin
        Fe::Notifier.notification(ref.email, # RECIPIENTS
                                  Fe.from_email, # FROM
# TODO
                                  "Reference Completed", # LIQUID TEMPLATE NAME
                                  {'first_name' => person.nickname,
                                   'site_url' => "#{APP_CONFIG['spgive_url']}/#{person.sp_gcx_site}/",
                                   'username' => person.user.username,
                                   'password' => person.user.password_plain}).deliver
=end

        # SpReferenceMailer.deliver_completed_confirmation(ref)
=begin
        Fe::Notifier.notification(ref.applicant_answer_sheet.person.email, # RECIPIENTS
                                  Fe.from_email, # FROM
                                  "Reference Completed To Applicant", # LIQUID TEMPLATE NAME
# TODO
                                  {'first_name' => person.nickname,
                                   'site_url' => "#{APP_CONFIG['spgive_url']}/#{person.sp_gcx_site}/",
                                   'username' => person.user.username,
                                   'password' => person.user.password_plain}).deliver
=end

        ref.applicant_answer_sheet.complete(ref)
      }

      event :start do
        transitions :to => :started, :from => :created
      end

      event :submit do
        transitions :to => :completed, :from => :started
        transitions :to => :completed, :from => :created
      end

      event :unsubmit do
        transitions :to => :started, :from => :completed
      end
    end

    alias_method :application, :applicant_answer_sheet
    delegate :applicant, to: :application

    def computed_visibility_cache_key
      return @computed_visibility_cache_key if @computed_visibility_cache_key
      return nil unless question # keep from crashing for tests
      answers = Fe::Answer.where(question_id: question.visibility_affecting_element_ids,
                                 answer_sheet_id: applicant_answer_sheet)
      answers.collect(&:cache_key).join('/')
    end

    def update_visible(page = nil)
      if visibility_cache_key == computed_visibility_cache_key
        visible
      else
        self.visible = question.visible?(applicant_answer_sheet, page)
        self.visibility_cache_key = computed_visibility_cache_key
        # save only these columns and don't check validations, but do record updated_at
        # as it is significant enough of an event that we probably want that to set updated_at
        Fe::ReferenceSheet.where(id: id).update_all(visibility_cache_key: self.computed_visibility_cache_key, visible: self.visible, updated_at: Time.now)
      end
    end

    def frozen?
      !%w(started created).include?(self.status)
    end

    def email_sent?() !self.email_sent_at.nil? end

    # send email invite
    def send_invite(host)
      return if self.email.blank?

      application = self.applicant_answer_sheet

      Notifier.notification(self.email,
                            Fe.from_email,
                            "Reference Invite",
                            {'reference_full_name' => self.name,
                             'applicant_full_name' => application.applicant.name,
                             'applicant_email' => application.applicant.email,
                             'applicant_home_phone' => application.applicant.phone,
                             'reference_url' => edit_fe_reference_sheet_url(self, :a => self.access_key, :host => host)}).deliver_now
      # Send notification to applicant
      Notifier.notification(applicant_answer_sheet.applicant.email, # RECIPIENTS
                            Fe.from_email, # FROM
                            "Reference Notification to Applicant", # LIQUID TEMPLATE NAME
                            {'applicant_full_name' => applicant_answer_sheet.applicant.name,
                             'reference_full_name' => self.name,
                             'reference_email' => self.email,
                             'application_url' => edit_fe_answer_sheet_url(applicant_answer_sheet, :host => host)}).deliver_now

      self.email_sent_at = Time.now
      self.save(:validate => false)

      true
    end

    def name
      [first_name, last_name].join(' ')
    end

    def reference
      self
    end

    def to_s
      name
    end

    def required?
      question.required?(applicant_answer_sheet)
    end

    def reference?
      true
    end

    # Can't rely on answer_sheet's implementation for old reference's that might have id's that may match an application id
    def question_sheet
      question_sheet_ref
    end

    def question_sheets
      [question_sheet_ref]
    end

    def question_sheet_ids
      [question_sheet_id].compact
    end

    def display_type
      question.label.split(/:| \(/).first
    end

    def optional?
      question.try(:hidden?, applicant_answer_sheet)
    end

    def required?
      !optional?
    end

    def all_affecting_questions_answered
      return false unless question
      question.visibility_affecting_questions.all? { |q| q.has_response?(applicant_answer_sheet) }
    end

    protected

    def set_question_sheet
      self.question_sheet_id = question.try(:related_question_sheet_id)
    end

    # if the email address has changed, we have to trash the old reference answers
    def reset_reference
      answers.destroy_all
      # Every time the email address changes, generate a new access_key
      generate_access_key
      self.email_sent_at = nil
      self.status = 'created'
    end

    def notify_old_reference_not_needed
      return unless email_sent_at_was.present? && email_was.present?
      notify_reference_not_needed(self, email_was, first_name_was, last_name_was)
    end

    def notify_reference_of_deletion
      return unless email_sent_at.present? && email.present?
      notify_reference_not_needed(self, email, first_name, last_name)
    end

    def notify_reference_not_needed(ref, ref_email, ref_first_name, ref_last_name)
      # inform referrer that they no longer need to fill out reference
      Fe::Notifier.notification(
        ref_email, # RECIPIENTS
        Fe.from_email, # FROM
        'Reference Deleted',
        { 'reference_full_name' => "#{ref_first_name} #{ref_last_name}",
          'applicant_full_name' => applicant_answer_sheet.applicant.name }
       ).deliver_now
    end

    def new_reference_requested?
      !allow_quiet_reference_email_changes && !new_record? && !completed? && email_changed?
    end
  end
end
