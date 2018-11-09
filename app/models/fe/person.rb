module Fe
  class Person < ApplicationRecord
    belongs_to :user, optional: true, :foreign_key => "fk_ssmUserId" # TODO need to migrate person columns to be more rails-like
    has_many   :email_addresses, class_name: '::EmailAddress', dependent: :destroy
    has_many   :phone_numbers, class_name: '::PhoneNumber', dependent: :destroy
    has_one    :current_address, -> { where("address_type = 'current'") }, class_name: '::Fe::Address', dependent: :destroy
    has_one    :permanent_address, -> { where("address_type = 'permanent'") }, class_name: '::Fe::Address', dependent: :destroy
    has_one    :emergency_address1, -> { where("address_type = 'emergency1'") }, class_name: 'Fe::Address', dependent: :destroy
    has_many   :addresses, dependent: :destroy
    has_many   :applications, class_name: Fe.answer_sheet_class

    def emergency_address
      emergency_address1
    end
    def emergency_address=(address)
      self.emergency_address1 = address
    end

    def create_emergency_address
      Address.create(:person_id => self.id, :address_type => 'emergency1')
    end

    def create_current_address
      Address.create(:person_id => self.id, :address_type => 'current')
    end

    def create_permanent_address
      Address.create(:person_id => self.id, :address_type => 'permanent')
    end

    def name
      [ first_name, last_name ].join(' ')
    end
  end

end
