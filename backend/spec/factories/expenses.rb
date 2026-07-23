FactoryBot.define do
  factory :expense do
    description { "MyString" }
    amount { "9.99" }
    date { Date.current }
    category
  end
end
