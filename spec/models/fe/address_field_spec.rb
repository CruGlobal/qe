# not sure if this is needed
require 'rails_helper'

describe Fe::AddressField do

  #if the address field style chosen to be default, then use google maps autocomplete
  describe '#ptemplate' do
    it 'default style' do
      addre = Fe::AddressField.new
      expect(addre.ptemplate).to eq("fe/text_field")
    end
  #if
    it 'essay style' do
      addre = Fe::AddressField.new
      addre.style = "essay"
      expect(addre.ptemplate).to eq("fe/text_area_field")
    end
  end
end

