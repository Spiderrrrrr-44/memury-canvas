# frozen_string_literal: true

require "spec_helper"

describe "Memury product routes", type: :routing do
  it "routes home, evidence workspace, risk center, plan, and semester memory independently" do
    expect(get: "/memury").to route_to("memury#index")
    expect(get: "/memury/learn/42").to route_to("memury#index", assignment_id: "42")
    expect(get: "/memury/risks").to route_to("memury#index")
    expect(get: "/memury/plan").to route_to("memury#index")
    expect(get: "/memury/memory").to route_to("memury#index")
    expect(get: "/memury/learning_graph").to route_to("memury#learning_graph")
    expect(post: "/memury/learning_graph/branches").to route_to("memury#continue_learning_graph")
    expect(patch: "/memury/learning_graph/current").to route_to("memury#select_learning_graph_node")
  end

  it "routes semester commands without overloading Canvas resources" do
    expect(post: "/memury/events").to route_to("memury#create_event")
    expect(patch: "/memury/events/7").to route_to("memury#update_event", id: "7")
    expect(delete: "/memury/events/7").to route_to("memury#destroy_event", id: "7")
    expect(post: "/memury/focus/pause").to route_to("memury#focus", command: "pause")
  end
end
