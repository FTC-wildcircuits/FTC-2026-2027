//
//  IdeasTabView.swift
//  FTCTeamHub
//
//  TAB 4 — Ideas & Whiteboard. Upvote-driven brainstorming feed, comment
//  threads, one-tap "promote to task", and an optional PencilKit sketch
//  canvas for rough mechanism dimensioning.
//

import SwiftUI
import SwiftData
import PencilKit
import UIKit

struct IdeasTabView: View {
    @Query(sort: \Idea.timestamp, order: .reverse) private var ideas: [Idea]
    @State private var isPresentingNewIdea = false

    var sortedByUpvotes: [Idea] { ideas.sorted { $0.upvoteCount > $1.upvoteCount } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedByUpvotes) { idea in
                    NavigationLink(value: idea) {
                        IdeaRow(idea: idea)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Ideas")
            .navigationDestination(for: Idea.self) { idea in IdeaDetailView(idea: idea) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewIdea = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isPresentingNewIdea) { NewIdeaSheet() }
        }
    }
}

private struct IdeaRow: View {
    @Bindable var idea: Idea
    @EnvironmentObject private var backend: MockBackendService
    @Environment(\.modelContext) private var context

    private var hasUpvoted: Bool {
        guard let uid = backend.currentUser?.id else { return false }
        return idea.upvoterIDs.contains(uid)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { toggleUpvote() } label: {
                VStack(spacing: 2) {
                    Image(systemName: hasUpvoted ? "arrowshape.up.circle.fill" : "arrowshape.up.circle")
                        .font(.title2)
                    Text("\(idea.upvoteCount)").font(.caption2.monospacedDigit())
                }
                .foregroundStyle(hasUpvoted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(idea.summary).font(.body.weight(.medium))
                Text("\(idea.authorName) · \(idea.comments.count) comment\(idea.comments.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                if idea.promotedToTask {
                    Label("On task board", systemImage: "checklist")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleUpvote() {
        guard let uid = backend.currentUser?.id, let name = backend.currentUser?.name else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let index = idea.upvoterIDs.firstIndex(of: uid) {
            idea.upvoterIDs.remove(at: index)
        } else {
            idea.upvoterIDs.append(uid)
            context.insert(ActivityEvent(authorID: uid, authorName: name, kind: .ideaUpvoted,
                                          message: "upvoted idea: \(idea.summary)"))
        }
    }
}

private struct IdeaDetailView: View {
    @Bindable var idea: Idea
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var backend: MockBackendService
    @State private var commentText = ""
    @State private var isPresentingCanvas = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(idea.summary).font(.title3.bold())
                if !idea.detail.isEmpty { Text(idea.detail) }

                Button {
                    isPresentingCanvas = true
                } label: {
                    Label(idea.sketchFileName == nil ? "Add Sketch" : "Edit Sketch", systemImage: "pencil.tip.crop.circle")
                }
                .buttonStyle(.bordered)

                Divider()

                Text("Comments").font(.headline)
                ForEach(idea.comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.authorName).font(.caption.weight(.semibold))
                        Text(comment.text).font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    TextField("Add a comment", text: $commentText)
                        .textFieldStyle(.roundedBorder)
                    Button("Post") { postComment() }.disabled(commentText.isEmpty)
                }

                if !idea.promotedToTask {
                    Button {
                        promoteToTask()
                    } label: {
                        Label("Promote to Task Board", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Idea")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingCanvas) {
            SketchCanvasView(idea: idea)
        }
    }

    private func postComment() {
        guard let uid = backend.currentUser?.id, let name = backend.currentUser?.name else { return }
        idea.comments.append(IdeaComment(authorID: uid, authorName: name, text: commentText))
        commentText = ""
    }

    private func promoteToTask() {
        guard let user = backend.currentUser else { return }
        let task = TaskItem(title: idea.summary, taskDescription: idea.detail, assigneeName: "Unassigned",
                             status: .toDo, priority: .medium, tags: ["From Idea"], authorID: user.id)
        context.insert(task)
        idea.promotedToTask = true
        context.insert(ActivityEvent(authorID: user.id, authorName: user.name, kind: .taskCreated,
                                      message: "promoted idea to task: \(idea.summary)"))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - PencilKit sketch canvas (bonus mandate item)

private struct SketchCanvasView: View {
    @Bindable var idea: Idea
    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()

    var body: some View {
        NavigationStack {
            PencilCanvasRepresentable(canvasView: $canvasView)
                .navigationTitle("Sketch")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            // Production: serialize canvasView.drawing to PNG/Data
                            // and persist to Documents/Attachments, storing the
                            // filename on idea.sketchFileName.
                            idea.sketchFileName = "sketch_\(idea.id.uuidString).png"
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvasView.backgroundColor = .systemBackground
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// MARK: - New idea sheet

private struct NewIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var backend: MockBackendService
    @State private var summary = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("One-line summary", text: $summary)
                TextField("Details", text: $detail, axis: .vertical)
            }
            .navigationTitle("New Idea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { post() }.disabled(summary.isEmpty)
                }
            }
        }
    }

    private func post() {
        guard let user = backend.currentUser else { return }
        let idea = Idea(authorID: user.id, authorName: user.name, summary: summary, detail: detail)
        context.insert(idea)
        context.insert(ActivityEvent(authorID: user.id, authorName: user.name, kind: .ideaPosted,
                                      message: "posted idea: \(summary)"))
        dismiss()
    }
}
