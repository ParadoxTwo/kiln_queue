Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "firings#index"

  resources :members, only: %i[index show]

  resources :pieces, only: %i[index show new create] do
    member do
      patch :mark_glazed
      patch :collect
    end
  end

  resources :firings, only: %i[index show new create] do
    resources :placements, only: :create
    member { post :complete }
  end

  get "reports/monthly_statement", to: "reports#monthly_statement", as: :monthly_statement
end
