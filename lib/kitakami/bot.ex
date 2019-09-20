defmodule Kitakami.Bot do
  import Nadia
  import Kitakami.Util
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    Logger.debug "Starting bot..."
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    Logger.debug "Initializing bot..."
    send self(), {:update, 0}
    {:ok, []}
  end

  def handle_info({:update, id}, state) do
    new_id = get_updates([offset: id]) |> process_updates

    :erlang.send_after(100, self(), {:update, new_id + 1})
    {:noreply, state}
  end

  def handle_info(_object, state), do: {:noreply, state}

  def process_updates({:ok, []}), do: -1
  def process_updates({:ok, updates}) do
    for update <- updates do
      update |> process_update
    end

    List.last(updates).update_id
  end

  def process_update(update) do
    Logger.debug "Processing update..."

    # Variable definitions
    {is_edited, info} = case update.message do
      nil -> {true, update.edited_message}
      msg -> {false, msg}
    end
    
    chat_id      = info.chat.id
    chat_title   = cond do
      Map.has_key?(info.chat, :title) -> case info.chat.title do
        nil -> "private"
        title -> title
      end
      true -> "private"
    end
    chat_type    = info.chat.type
    timestamp    = info.date
    user_id      = info.from.id
    first_name   = info.from.first_name
    last_name    = cond do
      Map.has_key?(info.from, :last_name) -> info.from.last_name
      true -> nil
    end
    username     = cond do
      Map.has_key?(info.from, :username) -> info.from.username
      true -> nil
    end
    message_id   = info.message_id
    message_text = cond do
      Map.has_key?(info, :text) -> case info.text do
        nil  -> info.caption
        text -> text
      end
      Map.has_key?(info, :caption) -> info.caption
      true -> nil
    end
    update_id    = update.update_id
    msg_opts     = [parse_mode: "Markdown"]

    original_message_text = cond do
      is_edited -> 
        original_update_id = query_data(:messages_index, message_id)
        original_message = query_data(:messages, original_update_id)
        
        case original_message do
          nil -> nil
          original_message -> original_message.message
        end
      true -> nil
    end

    # Default objects
    default_user_data = %{
      username: username,
      first_name: first_name,
      last_name: last_name,
      words: [],
      updated_at: timestamp
    }

    default_chat_data = %{
      title: chat_title,
      members: [],
      active_members: [],
      updated_at: timestamp
    }

    # Query current data
    user_data = case query_data(:users, user_id) do
      nil  ->
        store_data(:users, user_id, default_user_data)
        default_user_data
      data -> data |> Map.delete(:updated_at)
    end

    chat_data = case query_data(:chats, chat_id) do
      nil  ->
        if chat_type != "private" do
          store_data(:chats, chat_id, default_chat_data)
        end
        
        default_chat_data
      data -> data |> Map.delete(:updated_at)
    end

    # Update databases
    new_user_data = %{
      username: username,
      first_name: first_name,
      last_name: last_name,
      words: user_data.words,
      updated_at: timestamp
    }

    # Remove user from chat if they left it
    left_user_id = if update.message do
      if update.message.left_chat_member do
        update.message.left_chat_member.id
      end
    end

    new_chat_data = %{
      title: chat_title,
      members: Enum.uniq(chat_data.members ++ [user_id]) -- [left_user_id],
      active_members: chat_data.active_members -- [left_user_id],
      updated_at: timestamp
    }

    # Update user database if there's new data
    if user_data != Map.delete(new_user_data, :updated_at) do
      Logger.debug("Updating user #{user_id}...")
      store_data(:users, user_id, new_user_data)
    end

    # Update chat database if there's new data
    if chat_type != "private" do
      if chat_data != Map.delete(new_chat_data, :updated_at) do
        Logger.debug("Updating chat #{chat_id}...")
        store_data(:chats, chat_id, new_chat_data)
      end
    end

    # If there is message text, log the message and continue the process
    case message_text do
      nil -> nil
      message_text ->
        Logger.info("[#{chat_title}] #{first_name}: #{message_text}")

        new_message_data = %{
          message_id: message_id,
          chat_id: chat_id,
          user_id: user_id,
          message: message_text,
          updated_at: timestamp
        }

        store_data(:messages, update_id, new_message_data)
        store_data(:messages_index, message_id, update_id)

        # Re-query updated data
        user_data    = query_data(:users, user_id)
        chat_data    = query_data(:chats, chat_id)

        # Text matching and command methods
        # Will match commands first, and if nothing matches, will run the
        # match and notification process
        command = message_text
        |> String.split
        |> List.first
        |> String.replace("@KitakamiBot", "")

        case command do
          "/help" ->
            help_string = """
            I'll let you know if any words (RegExp strings) you specify are mentioned in chats that we're both in.

            You'll need to send me a private message in order for me to send you notifications.

            /start - starts notifying for the chat posted in
            /stop - stops notifying for the chat posted in
            /add [words] - add words to your list
            /del [words] - remove words from your list
            /words - lists all your current added words

            `[words]` is a single word or a list of words separated by spaces.
            """

            Nadia.send_message(chat_id, help_string, msg_opts)
          "/start" ->
            # Do nothing if the chat is private.
            unless chat_data == nil do
              # Only activate if the member is not active.
              member_is_active = Enum.member?(chat_data.active_members, user_id)
              
              response = case member_is_active do
                false ->
                  new_members = chat_data.active_members ++ [user_id]
                  new_chat_data = %{chat_data | active_members: new_members}
                  store_data(:chats, chat_id, new_chat_data)
                  
                  "Okay, this has been activated for you."
                true ->
                  "This chat has already been activated for you."
              end

              Nadia.send_message(chat_id, response)
            end
          "/stop" ->
            # Do nothing if the chat is private.
            unless chat_data == nil do
              # Only deactivate if the member is active
              member_is_active = Enum.member?(chat_data.active_members, user_id)
              
              response = case member_is_active do
                true ->
                  new_members = chat_data.active_members -- [user_id]
                  new_chat_data = %{chat_data | active_members: new_members}
                  store_data(:chats, chat_id, new_chat_data)
                  
                  "Okay, this has been deactivated for you."
                false ->
                  "This chat has not been activated for you."
              end

              Nadia.send_message(chat_id, response)
            end
          "/add" ->
            # Adds a list of words to a user's notification list.
            [_command | words] = message_text |> String.split

            response = unless words == [] do
              new_words = user_data.words ++ words
              new_user_data = %{user_data | words: new_words}
              store_data(:users, user_id, new_user_data)

              "Okay, added!"
            end

            Nadia.send_message(chat_id, response)
          "/del" ->
            # Removes a list of words to a user's notification list.
            [_command | words] = message_text |> String.split

            response = unless words == [] do
              new_words = user_data.words -- words
              new_user_data = %{user_data | words: new_words}
              store_data(:users, user_id, new_user_data)

              "Okay, removed!"
            end

            Nadia.send_message(chat_id, response)
          "/words" ->
            response = case user_data.words do
              []    -> "You don't have any words set."
              words -> "`" <> Enum.join(words, "`\n`") <> "`"
            end

            Nadia.send_message(chat_id, response, msg_opts)
          _command ->
            # Match and ping method, skipping private chats
            if chat_type != "private" do
              for member_id <- chat_data.active_members do
                # Skip if the current member sent the message
                if member_id != user_id do
                  member_data = query_data(:users, member_id)
        
                  # Match each word across the message string
                  matches = for word <- member_data.words do
                    String.match?(message_text, ~r"#{word}")
                  end
        
                  # If any word matched, notify the user
                  if Enum.member?(matches, true) do
                    edit_string = if original_message_text do
                      " (Edited)\n*Original Message:* #{original_message_text}"
                    end

                    notification_string = "From *#{chat_title}*#{edit_string}"
        
                    Nadia.send_message(member_id, notification_string, msg_opts)
                    Nadia.forward_message(member_id, chat_id, message_id)
                  end
                end
              end
            end
        end
    end
  end
end