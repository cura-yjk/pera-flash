Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  resources :conversations, only: [ :create, :show ] do
    member do
        post :generate_flashcards
    end
    resources :messages, only: [ :create ]
    resources :flashcards, only: [ :create ]   # step 6 — actually saving
  end

  get "/dashboard", to: "users#dashboard", as: :dashboard
  resources :flashcards, only: [:index, :show, :edit, :update, :destroy]

  resources :decks, only: [ :index, :create, :show, :destroy ] do
    member do
      get :export
    end
  end

end
