defmodule Daw.WebrtcPlaybackTest do
  @moduledoc """
  End-to-end proof that the studio actually plays.

  Everything else in the suite stops at the edge of WebRTC. This drives a real
  `ExWebRTC.PeerConnection` through the same signalling channel the browser
  uses, which is the only way to observe the thing that was broken twice: the
  pipeline cannot reach `playing` until the playback peer completes, so a
  signalling failure presents as a studio that renders perfectly and does
  nothing at all.
  """

  use ExUnit.Case, async: false

  alias Daw.{Graph, Pipeline}
  alias ExWebRTC.{PeerConnection, SessionDescription}
  alias Membrane.WebRTC.Signaling

  @moduletag :webrtc
  @timeout 20_000

  test "a peer that completes signalling gets audio, and the engine starts ticking" do
    signaling = Signaling.new()
    Signaling.register_peer(signaling, message_format: :ex_webrtc)

    {:ok, _supervisor, _pipeline} =
      Membrane.Pipeline.start_link(Pipeline,
        capture_signaling: Signaling.new(),
        player_signaling: signaling,
        plan: Graph.compile(Graph.initial_scene()),
        owner: self(),
        recording_dir: System.tmp_dir!()
      )

    {:ok, pc} = PeerConnection.start_link(ice_servers: [])

    # The sink offers as soon as it starts; answer it exactly as player.js does.
    offer = assert_receive_sdp(:offer)
    :ok = PeerConnection.set_remote_description(pc, offer)
    {:ok, answer} = PeerConnection.create_answer(pc)
    :ok = PeerConnection.set_local_description(pc, answer)
    Signaling.signal(signaling, %SessionDescription{type: :answer, sdp: answer.sdp})

    assert_connected(pc, signaling)

    # The engine's clock only runs once the pipeline reaches :playing, so any
    # telemetry at all is proof the whole chain came up.
    assert_receive {:daw_telemetry, telemetry}, @timeout
    assert map_size(telemetry) == 7

    # And the audio is real: the starting scene has an oscillator patched
    # through reverb into the master bus.
    assert telemetry["tone"].peak > 0.0
    assert telemetry["master"].peak > 0.0

    assert_receive {:ex_webrtc, ^pc, {:rtp, _track, _rid, _packet}}, @timeout
  end

  defp assert_receive_sdp(type) do
    receive do
      {:membrane_webrtc_signaling, _pid, %SessionDescription{type: ^type} = sdp, _metadata} ->
        sdp

      {:membrane_webrtc_signaling, _pid, _other, _metadata} ->
        assert_receive_sdp(type)
    after
      @timeout -> flunk("the sink never sent an SDP #{type}")
    end
  end

  # Trickles candidates in both directions until the peer connection is up.
  defp assert_connected(pc, signaling) do
    receive do
      {:ex_webrtc, ^pc, {:ice_candidate, candidate}} ->
        Signaling.signal(signaling, candidate)
        assert_connected(pc, signaling)

      {:ex_webrtc, ^pc, {:connection_state_change, :connected}} ->
        :ok

      {:membrane_webrtc_signaling, _pid, %ExWebRTC.ICECandidate{} = candidate, _metadata} ->
        :ok = PeerConnection.add_ice_candidate(pc, candidate)
        assert_connected(pc, signaling)

      {:ex_webrtc, ^pc, _other} ->
        assert_connected(pc, signaling)

      {:membrane_webrtc_signaling, _pid, _other, _metadata} ->
        assert_connected(pc, signaling)
    after
      @timeout -> flunk("the peer connection never reached :connected")
    end
  end
end
