require 'rails_helper'

RSpec.describe "Api::Expenses", type: :request do
  let!(:food_category) { Category.create!(name: "Food") }
  let!(:transport_category) { Category.create!(name: "Transport") }

  describe "GET /api/expenses" do
    let!(:newer_expense) { Expense.create!(description: "Taxi", amount: 50.00, category: transport_category, date: Date.today) }
    let!(:older_expense) { Expense.create!(description: "Lunch", amount: 100.00, category: food_category, date: Date.today.prev_month) }

    it "returns all expenses with category information" do
      get "/api/expenses"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.length).to eq(2)
    end

    it "returns expenses in descending order by date" do
      get "/api/expenses"

      json = JSON.parse(response.body)
      expect(json.first["id"]).to eq(newer_expense.id)
      expect(json.last["id"]).to eq(older_expense.id)
    end

    it "filters by year and month using the expense date" do
      get "/api/expenses", params: { year: Date.today.year, month: Date.today.month }

      json = JSON.parse(response.body)
      expect(json.map { |expense| expense["id"] }).to eq([ newer_expense.id ])
    end
  end

  describe "POST /api/expenses" do
    context "with valid parameters" do
      let(:valid_params) do
        {
          expense: {
            description: "Team Lunch",
            amount: 150.50,
            category_id: food_category.id,
            date: Date.today
          }
        }
      end

      it "creates a new expense" do
        expect {
          post "/api/expenses", params: valid_params, as: :json
        }.to change(Expense, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["description"]).to eq("Team Lunch")
        expect(json["amount"]).to eq(150.5)
      end
    end

    context "with invalid parameters" do
      it "with negative amounts" do
        invalid_params = {
          expense: {
            description: "Invalid expense",
            amount: -100.00,
            category_id: food_category.id,
            date: Date.today
          }
        }

        expect {
          post "/api/expenses", params: invalid_params, as: :json
        }.to change(Expense, :count).by(1)

        expect(response).to have_http_status(:created)
      end

      it "with empty descriptions" do
        invalid_params = {
          expense: {
            description: "",
            amount: 100.00,
            category_id: food_category.id,
            date: Date.today
          }
        }

        expect {
          post "/api/expenses", params: invalid_params, as: :json
        }.to change(Expense, :count).by(1)

        expect(response).to have_http_status(:created)
      end

      it "with a future date" do
        invalid_params = {
          expense: {
            description: "Future expense",
            amount: 100.00,
            category_id: food_category.id,
            date: Date.tomorrow
          }
        }

        expect {
          post "/api/expenses", params: invalid_params, as: :json
        }.not_to change(Expense, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PUT /api/expenses/:id" do
    it "updates an expense's category via category_id" do
      expense = Expense.create!(description: "Lunch", amount: 100.00, category: food_category, date: Date.today)

      put "/api/expenses/#{expense.id}", params: { expense: { category_id: transport_category.id } }, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["category"]).to eq("Transport")
    end
  end
end
