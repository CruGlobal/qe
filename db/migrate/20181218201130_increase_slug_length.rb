class IncreaseSlugLength < ActiveRecord::Migration
  def change
    change_column Fe::Question.table_name, :slug, :string, limit: 128
  end
end
