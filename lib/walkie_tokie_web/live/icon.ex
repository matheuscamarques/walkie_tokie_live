# defmodule WalkieTokieWeb.WalkieTokieLive.Icon do
#   use Phoenix.Component

#   def render(assigns) do
#     ~H"""
#     <svg
#       xmlns="http://www.w3.org/2000/svg"
#       width="24"
#       height="24"
#       viewBox="0 0 24 24"
#       fill="none"
#       stroke="currentColor"
#       stroke-width="2"
#       stroke-linecap="round"
#       stroke-linejoin="round"
#       class={assigns.class}
#     >
#       <%= case assigns.name do %>
#         <% :mic -> %>
#           <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"></path>
#           <path d="M19 10v2a7 7 0 0 1-14 0v-2"></path>
#           <line x1="12" y1="19" x2="12" y2="23"></line>
#           <line x1="8" y1="23" x2="16" y2="23"></line>
#         <% :radio -> %>
#           <path d="M21 5H3a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2z"></path>
#           <path d="M12 9v6"></path>
#           <path d="M8 9v6"></path>
#           <path d="M16 9v6"></path>
#         <% :user -> %>
#           <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
#           <circle cx="12" cy="7" r="4"></circle>
#         <% :volume_2 -> %>
#           <polygon points="11 5 6 9 6 15 11 19 16 15 16 9 11 5"></polygon>
#           <path d="M19.07 8.93a6 6 0 0 1 0 6.14"></path>
#           <path d="M22.41 5.59a10 10 0 0 1 0 12.82"></path>
#       <% end %>
#     </svg>
#     """
#   end
# end
