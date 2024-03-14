defmodule LCRDT.Participant do
  alias LCRDT.Logging
  alias LCRDT.Network
  alias LCRDT.Store
  import LCRDT.Injections
  import LCRDT.Injections.Crash
  import LCRDT.Injections.Lag
  use GenServer

  # TODO: Defer follower recovery if coordinator is recovering.

  @coordinator_storage :coordinator_state

  # All state (only some of it relevant to non-leader)
  # Name - the PID of the process
  # Application PID - the PID of the linked application layer
  # Logs - the persistant storage log.
  # Followers - the PID of the followers (incl. self)
  # In progress
  # Votes - map of PID and vote
  defmodule PState do
    defstruct [
      :name,
      :application_pid,
      :logs,
      :followers,
      :tid,
      :body,
      :body_previous,
      queue: [],
      stage: :idle,
      votes: Map.new(),
      crashpoints: 0,
      lagpoints: 0,
    ]
  end

  def start_link({name, application_pid}) do
    IO.puts("#{__MODULE__}/#{name}: Starting")
    GenServer.start_link(__MODULE__, {name, application_pid}, name: name);
  end

  def allocate(application_pid, lease_amount) do
    # Body = {:allocate, amount, allocater_pid}
    GenServer.cast(Network.coordinator(), {:start, {:allocate, lease_amount, application_pid}})
  end

  def deallocate(application_pid, lease_amount) do
    # Body = {:deallocate, amount, deallocater_pid}
    GenServer.cast(Network.coordinator(), {:start, {:deallocate, lease_amount, application_pid}})
  end

  @impl true
  def init({name, application_pid}) do
    # TODO: Check if leader is alive during follower recovery.
    followers =
      unless is_coordinator(name) do
        # We indicate that we are a follower.
        GenServer.cast(Network.coordinator(), {:new_follower, name})
        []
      else
        [name]
      end

    # Handle recoveries.
    # If we have an uncommited change in the log, we need to handle this.
    logs = Logging.read(name)
    # Go through all the changes in the log and apply them.
    # This is such that we can get the CRDT into the correct state.
    apply_logs(logs, application_pid)

    # Read the new state.
    state0 = %PState{name: name, application_pid: application_pid, logs: logs, followers: followers}
    state1 =
      if is_coordinator(name) do
        # Logs are handled separately so we will purge those.
        Map.merge(state0, Store.read(@coordinator_storage))
      else
        state0
      end

    # Different strategies depending on if coordinator or regular server.
    state2 =
      if is_coordinator(name) do
        # Check what state we are in.
        out(name, "Started coordinator recovery")
        cond do
          # We've started but we haven't sent out the prepares yet.
          state1.stage == :started ->
            out(name, "Recovering in started state")
            # We send out the prepares.
            Enum.each(state1.followers, fn follower_pid -> resend_last_prepare_request(state1, follower_pid) end)
            # We have to change the state too.
            state2 = %{state1 | stage: :prepared}
            snapshot_coordinator(state2)
            state2
          # We've sent all prepares, but we're not sure if we have received all responses.
          state1.stage == :prepared ->
            out(name, "Recovering in prepared state")
            # Take the ones for whom we do not yet know their response.
            unknown = state1.followers -- Map.keys(state1.votes)
            # We re-send prepares to those.
            Enum.each(unknown, fn follower_pid -> GenServer.cast(follower_pid, {:recovery, state1.tid}) end)
            state1
          # Finalized, so we need to re-send finalized messages.
          state1.stage == :finalized ->
            out(name, "Recovering in finalized state")
            # We re-send out our responses.
            Enum.each(state1.followers, fn follower_pid ->
              unless follower_pid == name do
                # Note that here we use the BODY not the PREVIOUS BODY because they have not switched yet.
                resend_last_outcome(state1, follower_pid, state1.tid, state1.body)
              end
            end)
            state1
          # We're idle, so we don't need to recover.
          true ->
            state1
        end
      else
        out(name, "Started follower recovery")
        # Check for retransmissions.
        case Logging.peek_change(logs) do
          # We have to re-transmit our vote response because we're not sure what happened.
          # If a decision was made, the coordinator will recognize this is a retransmission and tell us what happened.
          {:found, tid} ->
            # We only send actions we actually commit, so this will always be a commit.
            # We can pretty easily recover from this.
            GenServer.cast(Network.coordinator(), {:vote_response, tid, name, :commit})
          # At this point we do not know what we are doing, and recovery is a bit more tricky.
          :not_found ->
            # We have to send an explicit recovery signal and let the coordinator take charge in our recovery.
            GenServer.cast(Network.coordinator(), {:recovery, name})
        end
        state1
      end
    {:ok, state2}
  end

  @impl true
  def handle_cast({:start, body} = req, state1) do
    cond do
      # Edge case: trying to start with non-coordinator.
      not is_coordinator(state1) ->
        out(state1, "ERROR, only the coordinator can handle starts")
        {:noreply, state1}
      # Edge case: trying to start during a concurrent transaction.
      state1.stage != :idle ->
        out(state1, "Received start in running state, queueing up")
        {:noreply, %{state1 | queue: state1.queue ++ [req]}}
      # Regular execution.
      true ->
        # We assign this a new transaction ID.
        state2 = %{state1 | stage: :started, tid: :erlang.make_ref(), body: body}
        snapshot_coordinator(state2)
        if activated(state2.crashpoints, before_prepare_request()) do
          raise("hit before_prepare_request crashpoint")
        end
        # Now we must tell all followers to prepare.
        Enum.each(state2.followers, fn follower_pid ->
          GenServer.cast(follower_pid, {:prepare_request, state2.tid, body})
          out(state2, "Sent a prepare request to follower #{follower_pid}")
        end)
        # We now set the state to be in preparation, this is needed for recovery.
        state3 = %{state2 | stage: :prepared}
        snapshot_coordinator(state3)
        if activated(state3.crashpoints, after_prepare_request()) do
          raise("hit after_prepare_request crashpoint")
        end
        {:noreply, state3}
    end
  end

  @impl true
  def handle_cast({:new_follower, their_pid}, state1) do
    out(state1, "Discovered follower with PID #{their_pid}")
    # We only want to add them if they do not exist. If they crashed and restart, they will exist.
    followers = if Enum.member?(state1.followers, their_pid), do: state1.followers, else: [their_pid | state1.followers]
    state2 = %{state1 | followers: followers}
    {:noreply, state2}
  end

  @impl true
  def handle_cast({:prepare_request, tid, body}, state1) do
    # Crashpoint: pretend prepare was not received.
    if activated(state1.crashpoints, before_prepare()) do
      raise("hit before_prepare crashpoint")
    end
    # First, we have to make a call to the application layer to determine what to do.
    # The application layer will tell us either OK or abort.
    {vote, state2} = case GenServer.call(state1.application_pid, {:prepare, body}, :infinity) do
      :ok ->
        # If this is okay, we need to add it to our own log.
        logs = Logging.log_change(state1.name, state1.logs, tid, body)
        {:ok, %{state1 | logs: logs}}
      :abort ->
        # If this is not okay, then we just need to return the message.
        {:abort, state1}
    end
    # Crashpoint: prepare response was not sent.
    if activated(state1.crashpoints, during_prepare()) do
      raise("hit during_prepare crashpoint")
    end
    # Send the response to the actual coordinator.
    GenServer.cast(Network.coordinator(), {:vote_response, tid, state2.name, vote})
    out(state2, "Sent a vote response to coodinator: #{vote}")
    # Crashpoint: prepare response was received.
    if activated(state1.crashpoints, after_prepare()) do
      raise("hit after_prepare crashpoint")
    end
    {:noreply, state2}
  end

  @impl true
  def handle_cast({:vote_response, tid, vote_caster, vote}, state1) do
    cond do
      # First we check if we have a transaction going on right now.
      # If not, it means that this is a process trying to catch up and we can do so.
      state1.stage == :idle ->
        # We need to re-send the last outcome to get them up to speed.
        resend_last_outcome(state1, vote_caster, tid, state1.body_previous)
        # We continue.
        {:noreply, state1}
      # Next we check if we received a vote for this round.
      # It could be that a process crashed after committing, and they never got the response.
      # In the meantime, we started a new round.
      tid != state1.tid ->
        # They will re-send this vote, but the TID will be different.
        # In this case, we need to re-send the last outcome.
        resend_last_outcome(state1, vote_caster, tid, state1.body_previous)
        # We also need to get them up to speed on the decision we are making right now.
        # Sending it in this order requires FIFO links but we have these in Elixir.
        resend_last_prepare_request(state1, vote_caster)
        # We continue.
        {:noreply, state1}
      # We have a new vote response here.
      true ->
        # Handle vote response messages.
        state2 = %{state1 | votes: Map.put(state1.votes, vote_caster, vote)}
        # We wait for all votes to arrive before we possibly abort.
        # This is so we can be sure we don't get out of order. I think that could be an edge case.
        state3 = try_action(state2)
        # Last but not least, we update the state.
        {:noreply, state3}
    end
  end

  @impl true
  def handle_cast({:finalize, tid, outcome, body}, state) do
    {:noreply, finalize(tid, outcome, body, state)}
  end

  def handle_cast({:recovery, tid}, state) when is_reference(tid) do
    out(state, "Retransmitting vote after coordinator crash")
    # Handled by followers.
    # In this situation, all votes should be re-sent for the specific transaction ID.
    # Since we have a FIFO mailbox, we know that IF the prepare came, it came before this.
    # So we can check the log for this TID. If there is an uncommitted, change, OK. Else, abort.
    vote = Logging.find_vote(state.logs, tid)
    GenServer.cast(Network.coordinator(), {:vote_response, tid, state.name, vote})
    {:noreply, state}
  end

  def handle_cast({:recovery, recovered_pid}, state1) do
    # Handled by coordinator.
    # The only thing we need to do here is if prepares have been sent out, we abort.
    # We have nothing in the log for this transaction, so we either:
    # 1) Never received this message; or
    # 2) Received this message and aborted it, hence we did not write to the log.
    # So, to be safe, we must abort.
    # The rest of the error handling is implemented elsewhere.
    if state1.stage == :prepared do
      # Here we have to hard abort.
      # We can't send the abort message since we don't have the TID.
      # But we can manipulate internal state and re-call the function.
      out(state1, "We have to abort due to crashed follower")
      state2 = %{state1 | votes: Map.put(state1.votes, recovered_pid, :abort)}
      state3 = try_action(state2)
      {:noreply, state3}
    else
      # Otherwise we ignore it, it will figure itself out.
      {:noreply, state1}
    end
  end

  def handle_cast({:inject_fault, crashpoints, lagpoints}, state1) do
    out(state1, "New injections, crashing at #{crashpoints} and lagging at #{lagpoints}")
    new_crashpoints = union(state1.crashpoints, crashpoints)
    new_lagpoints = union(state1.lagpoints, lagpoints)
    state2 = %{state1 | crashpoints: new_crashpoints, lagpoints: new_lagpoints}
    {:noreply, state2}
  end

  defp try_action(state2) do
    # We can only do something once we have all votes.
    if map_size(state2.votes) == length(state2.followers) do
      num_aborts = Enum.count(Map.values(state2.votes), fn x -> x == :abort end)
      out(state2, "Received #{num_aborts} aborts")
      # Naturally, we abort if at least one node says to abort.
      action = if num_aborts == 0, do: :commit, else: :abort
      # We finalize ourselves FIRST so we can do proper crash recovery.
      state3 = %{finalize(state2.tid, action, state2.body, state2, true) | stage: :finalized}
      snapshot_coordinator(state3)
      out(state3, "Finalized own state")
      if activated(state3.crashpoints, before_finalize()) do
        raise("hit before_finalize crashpoint")
      end
      if activated(state3.lagpoints, finalize()) do
        :timer.sleep(:rand.uniform(10))
      end
      # Broadcast the outcome to all followers.
      Enum.each(state3.followers, fn follower_pid ->
        unless follower_pid == state3.name do
          GenServer.cast(follower_pid, {:finalize, state3.tid, action, state3.body})
          out(state2, "Sent a finalize request to follower #{follower_pid}")
        end
      end)
      # We are done with this now!
      # We can reset the state back to blank now.
      out(state3, "Resetting the state")
      state4 = %{state3 | tid: nil, body: nil, body_previous: state3.body, stage: :idle, votes: Map.new()}
      snapshot_coordinator(state4)
      # Go through queue.
      case state4.queue do
        [] ->
          state4
        [req | rest] ->
          # Tell itself to restart.
          state5 = %{state4 | queue: rest}
          snapshot_coordinator(state5)
          GenServer.cast(Network.coordinator(), req)
          state5
      end
    else
      # Noop.
      state2
    end
  end

  defp finalize(tid, outcome, body, state, force \\ false) do
    logs =
      if (Logging.find_outcome(state.logs, tid) == :not_found) or force do
        out(state, "Received new finalize")
        case outcome do
          :commit ->
            GenServer.cast(state.application_pid, {:commit, body})
            Logging.log_commit(state.name, state.logs, tid)
          :abort ->
            GenServer.cast(state.application_pid, {:abort, body})
            Logging.log_abort(state.name, state.logs, tid)
        end
      else
        out(state, "Re-received finalize")
        state.logs
      end
    %{state | logs: logs}
  end

  defp apply_logs(logs, application_pid) do
    # We play through in the correct oder.
    Logging.run(logs, application_pid)
  end

  defp resend_last_outcome(state, syncing_pid, last_tid, which_body) do
    case Logging.find_outcome(state.logs, last_tid) do
      :not_found ->
        out(state, "ERROR, could not find last outcome of a crashed process, this is a bug")
      {:found, outcome} ->
        out(state, "Sending last outcome to #{syncing_pid}")
        GenServer.cast(syncing_pid, {:finalize, last_tid, outcome, which_body})
    end
  end

  defp resend_last_prepare_request(state, syncing_pid) do
    out(state, "Re-sent prepare request to #{syncing_pid}")
    GenServer.cast(syncing_pid, {:prepare_request, state.tid, state.body})
  end

  defp snapshot_coordinator(state1) do
    # We NEVER save crashpoints or lagpoints.
    # Logs should be cleared as they are recovered separately.
    state2 = %{state1 | crashpoints: neutral(), lagpoints: neutral()}
    state3 = Map.delete(state2, :logs)
    Store.write(@coordinator_storage, state3)
    :ok
  end

  defp is_coordinator(name) when is_atom(name), do: name == Network.coordinator()
  defp is_coordinator(state), do: state.name == Network.coordinator()

  defp out(state, message) when (not is_atom(state)) do
    unless LCRDT.Environment.is_silent(), do: IO.puts("#{__MODULE__}/#{state.name}: #{message}")
  end
  defp out(name, message), do: out(%{name: name}, message)
end
