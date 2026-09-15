Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Makes the app installable to a phone's home screen. The manifest is linked
  # from the layout; the service worker exists mainly because Chrome will not
  # offer to install a site without one.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  resources :conversations, only: [ :index, :new, :create, :show ] do
    member do
        post :generate_flashcards
    end
    resources :messages, only: [ :create ]
    # Pera's reply, streamed. GET because it is replay-safe: it answers only
    # when the conversation is waiting for a reply.
    get "reply", to: "messages#stream"
    resources :flashcards, only: [ :create ]   # step 6 — actually saving
  end

  get "/dashboard", to: "users#dashboard", as: :dashboard
  patch "/furigana", to: "users#toggle_furigana", as: :toggle_furigana
  patch "/language", to: "users#update_locale", as: :language
  resources :flashcards, only: [:index, :show, :edit, :update, :destroy]

  # Studying cards. Across every deck, or within one.
  get "/review", to: "reviews#show", as: :review
  patch "/review/:id", to: "reviews#update", as: :review_card

  # Quizzing over them. Shares the review schedule -- see QuizzesController.
  get "/quiz", to: "quizzes#show", as: :quiz
  post "/quiz", to: "quizzes#answer", as: :quiz_answer

  resources :decks, only: [ :index, :create, :show, :destroy ] do
    member do
      get :export
    end

    # Nested, not member: this gives :deck_id, so the card's own :id stays
    # unambiguous in the update route.
    get "review", to: "reviews#show", as: :review
    patch "review/:id", to: "reviews#update", as: :review_card
    get "quiz", to: "quizzes#show", as: :quiz
    post "quiz", to: "quizzes#answer", as: :quiz_answer
  end

end
