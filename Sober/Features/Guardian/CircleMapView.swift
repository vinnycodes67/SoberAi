import CoreLocation
import MapKit
import SwiftUI
import UIKit

// 0.5s: a full-bleed map with one luminous family marker and a compact glass status dock.
// User: a guardian checking that someone arrived safely, or the person controlling their own sharing.
// Emotional intent: calm awareness with unmistakable freshness and privacy state—not surveillance theater.
struct CircleMapView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var position: MapCameraPosition = .automatic
  @State private var showingStopConfirmation = false
  @State private var showingFounderSample = false
  @State private var founderSampleDate = Date()

  var body: some View {
    NavigationStack {
      ZStack {
        map
        if mapPoint == nil { emptyMapState }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        statusDock
      }
      .navigationTitle("Circle Map")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task(id: model.guardianSession?.relationshipID) {
        while !Task.isCancelled, model.guardianSession != nil {
          await model.refreshGuardian()
          try? await Task.sleep(for: .seconds(5))
        }
      }
      .onAppear { focusMap(animated: false) }
      .onChange(of: mapPoint?.id) { _, _ in focusMap(animated: true) }
      .confirmationDialog(
        "Stop sharing your location?",
        isPresented: $showingStopConfirmation,
        titleVisibility: .visible
      ) {
        Button("Stop sharing", role: .destructive) {
          Task { await model.stopGuardianLocationSharing() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Sober stops collecting immediately and asks the relay to remove your last visible map location.")
      }
    }
  }

  private var map: some View {
    Map(position: $position, interactionModes: .all) {
      if let point = mapPoint {
        MapCircle(center: point.coordinate, radius: max(point.accuracy, 8))
          .foregroundStyle(Palette.primary.opacity(0.12))
          .stroke(Palette.primary.opacity(0.42), lineWidth: 1)

        Annotation("", coordinate: point.coordinate, anchor: .bottom) {
          memberMarker(point)
        }
      }
    }
    .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .ignoresSafeArea(edges: .bottom)
  }

  private var emptyMapState: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(.ultraThinMaterial)
          .frame(width: 72, height: 72)
        Image(systemName: emptyIcon)
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(Palette.primary)
      }
      Text(emptyTitle)
        .font(.title3.weight(.semibold))
      Text(emptyDetail)
        .font(.subheadline)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 280)
    }
    .padding(22)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .padding(.horizontal, 28)
    .allowsHitTesting(false)
  }

  private var statusDock: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          Circle().fill(statusTint.opacity(0.16))
          Image(systemName: statusIcon)
            .foregroundStyle(statusTint)
        }
        .frame(width: 46, height: 46)

        VStack(alignment: .leading, spacing: 3) {
          Text(statusTitle)
            .font(.headline)
          Text(statusDetail)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }

      if let error = model.guardianError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(Palette.warning)
      }

      personControls

      Label(
        retentionDetail,
        systemImage: "hand.raised.fill"
      )
      .font(.caption)
      .foregroundStyle(Palette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Capsule()
        .fill(.white.opacity(0.2))
        .frame(width: 36, height: 4)
        .padding(.top, 7)
    }
  }

  @ViewBuilder
  private var personControls: some View {
    if model.isFounderPreview, !model.guardianRelationshipIsActive {
      Button {
        if !showingFounderSample { founderSampleDate = Date() }
        showingFounderSample.toggle()
      } label: {
        Label(
          showingFounderSample ? "Hide sample location" : "Preview sample location",
          systemImage: showingFounderSample ? "eye.slash" : "eye"
        )
      }
      .buttonStyle(SecondaryActionButtonStyle(tint: Palette.item2))

      Text("Founder preview only · this sample is not uploaded or presented as a real person.")
        .font(.caption)
        .foregroundStyle(Palette.warning)
    } else if model.guardianSession?.role == .person, model.guardianRelationshipIsActive {
      if !model.guardianLocationSharingIsEnabled {
        Button {
          Task { await model.enableGuardianLocationSharing() }
        } label: {
          Label("Share my location", systemImage: "location.fill")
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(model.guardianIsWorking)
      } else {
        switch model.guardianLocationAuthorization {
        case .foregroundOnly:
          Button {
            model.requestGuardianBackgroundLocationAccess()
          } label: {
            Label("Allow background updates", systemImage: "location.circle.fill")
          }
          .buttonStyle(PrimaryActionButtonStyle())

          Text("Right now the map updates only while Sober is open. Background access keeps it current after you leave the app.")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)

        case .denied, .restricted, .unavailable:
          Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
          } label: {
            Label("Open Location Settings", systemImage: "gear")
          }
          .buttonStyle(SecondaryActionButtonStyle(tint: Palette.warning))

        case .notDetermined, .background:
          EmptyView()
        }

        Button("Stop sharing", role: .destructive) {
          showingStopConfirmation = true
        }
        .font(.subheadline.weight(.semibold))
        .disabled(model.guardianIsWorking)
      }
    }
  }

  private func memberMarker(_ point: CircleMapPoint) -> some View {
    VStack(spacing: 5) {
      ZStack {
        Circle()
          .fill(.ultraThinMaterial)
          .frame(width: 58, height: 58)
          .overlay {
            Circle().stroke(Palette.primary, lineWidth: 3)
          }
          .shadow(color: .black.opacity(0.32), radius: 10, y: 5)
        Text(point.initials)
          .font(.headline.weight(.bold))
          .foregroundStyle(Palette.textPrimary)
      }
      Text(point.name)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.72), in: Capsule())
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(point.name), \(freshnessText(for: point.capturedAt)), accuracy approximately \(Int(point.accuracy.rounded())) meters")
  }

  private var mapPoint: CircleMapPoint? {
    if showingFounderSample {
      return CircleMapPoint(
        name: "Alex Rivera · SAMPLE",
        latitude: 41.8827,
        longitude: -87.6233,
        accuracy: 14,
        capturedAt: founderSampleDate
      )
    }
    guard model.guardianRelationshipIsActive else { return nil }
    if model.guardianSession?.role == .person, let update = model.guardianLocalLocation {
      return CircleMapPoint(
        name: personName,
        latitude: update.coordinate.latitude,
        longitude: update.coordinate.longitude,
        accuracy: update.coordinate.horizontalAccuracy,
        capturedAt: update.capturedAt
      )
    }
    guard let location = model.guardianLocationSharing?.latestLocation,
      let capturedAt = location.capturedDate
    else { return nil }
    return CircleMapPoint(
      name: personName,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.horizontalAccuracyMeters,
      capturedAt: capturedAt
    )
  }

  private var personName: String {
    let name = model.guardianRelationship?.personDisplayName
      ?? model.userProfile.trimmedName
    return name.isEmpty ? "Your person" : name
  }

  private var statusTitle: String {
    if showingFounderSample { return "Sample location preview" }
    guard model.guardianRelationshipIsActive else { return "Connect your Circle" }
    guard model.guardianLocationSharing?.enabled == true else {
      return model.guardianSession?.role == .person ? "Location sharing is off" : "Location unavailable"
    }
    guard let point = mapPoint else { return "Waiting for a location" }
    return freshnessText(for: point.capturedAt)
  }

  private var statusDetail: String {
    if showingFounderSample {
      return "Illustrative marker, accuracy radius, and freshness treatment for founder review."
    }
    guard model.guardianRelationshipIsActive else {
      return "Create a Guardian relationship before sharing a family location."
    }
    guard model.guardianLocationSharing?.enabled == true else {
      return model.guardianSession?.role == .person
        ? "Your guardian cannot see you on the map."
        : "They are not sharing right now. This does not indicate an emergency."
    }
    guard let point = mapPoint else {
      return "Sharing is on, but no reliable location has arrived yet."
    }
    return "Approximately ±\(Int(point.accuracy.rounded())) m · \(backgroundStatus)"
  }

  private var backgroundStatus: String {
    guard model.guardianSession?.role == .person else { return "latest device update" }
    return model.guardianLocationAuthorization == .background
      ? "background updates on" : "updates while app is open"
  }

  private var statusIcon: String {
    if showingFounderSample { return "eye.fill" }
    if !model.guardianRelationshipIsActive { return "person.2.slash" }
    if model.guardianLocationSharing?.enabled != true { return "location.slash.fill" }
    return mapPoint == nil ? "location.magnifyingglass" : "location.fill"
  }

  private var statusTint: Color {
    if showingFounderSample { return Palette.item2 }
    if !model.guardianRelationshipIsActive || model.guardianLocationSharing?.enabled != true {
      return Palette.textSecondary
    }
    guard let point = mapPoint else { return Palette.warning }
    return Date().timeIntervalSince(point.capturedAt) <= 5 * 60 ? Palette.primary : Palette.warning
  }

  private var emptyIcon: String {
    model.guardianRelationshipIsActive ? "location.slash.fill" : "person.2.slash"
  }

  private var emptyTitle: String {
    model.guardianRelationshipIsActive ? "No shared location" : "Your Circle starts here"
  }

  private var emptyDetail: String {
    model.guardianRelationshipIsActive
      ? "The map stays quiet until location sharing is deliberately turned on."
      : "Connect two devices in Guardian Mode, then choose whether to share location."
  }

  private var retentionDetail: String {
    showingFounderSample
      ? "The sample stays on this screen and is never sent to the relay."
      : "Only the newest location is retained for up to 24 hours. Sharing can be stopped at any time."
  }

  private func focusMap(animated: Bool) {
    guard let point = mapPoint else { return }
    let update = {
      position = .camera(MapCamera(
        centerCoordinate: point.coordinate,
        distance: max(900, point.accuracy * 8),
        heading: 0,
        pitch: 28
      ))
    }
    if animated {
      withAnimation(.easeInOut(duration: 0.55), update)
    } else {
      update()
    }
  }

  private func freshnessText(for date: Date) -> String {
    let seconds = max(0, Date().timeIntervalSince(date))
    if seconds < 45 { return "Updated just now" }
    if seconds < 120 { return "Updated 1 minute ago" }
    if seconds < 60 * 60 { return "Updated \(Int(seconds / 60)) minutes ago" }
    if seconds < 2 * 60 * 60 { return "Updated 1 hour ago" }
    return "Updated \(Int(seconds / 3600)) hours ago"
  }
}

private struct CircleMapPoint: Identifiable, Equatable {
  let name: String
  let latitude: Double
  let longitude: Double
  let accuracy: Double
  let capturedAt: Date

  var id: String { "\(latitude)-\(longitude)-\(capturedAt.timeIntervalSince1970)" }
  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
  var initials: String {
    let words = name.split(separator: " ").prefix(2)
    let value = words.compactMap(\.first).map(String.init).joined()
    return value.isEmpty ? "S" : value.uppercased()
  }
}
