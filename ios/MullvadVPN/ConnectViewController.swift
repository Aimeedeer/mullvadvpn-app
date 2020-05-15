//
//  ConnectViewController.swift
//  MullvadVPN
//
//  Created by pronebird on 20/03/2019.
//  Copyright © 2019 Mullvad VPN AB. All rights reserved.
//

import Combine
import UIKit
import MapKit
import NetworkExtension
import os

class CustomOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let drawRect = self.rect(for: mapRect)
        context.setFillColor(UIColor.secondaryColor.cgColor)
        context.fill(drawRect)
    }
}

class ConnectViewController: UIViewController, RootContainment, TunnelControlViewControllerDelegate, MKMapViewDelegate {

    @IBOutlet var secureLabel: UILabel!
    @IBOutlet var countryLabel: UILabel!
    @IBOutlet var cityLabel: UILabel!
    @IBOutlet var connectionPanel: ConnectionPanelView!
    @IBOutlet var mapView: MKMapView!

    private var setRelaysSubscriber: AnyCancellable?
    private var startStopTunnelSubscriber: AnyCancellable?
    private var tunnelStateSubscriber: AnyCancellable?

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    var preferredHeaderBarStyle: HeaderBarStyle {
        switch tunnelState {
        case .connecting, .reconnecting, .connected:
            return .secured

        case .disconnecting, .disconnected:
            return .unsecured
        }
    }

    var prefersHeaderBarHidden: Bool {
        return false
    }

    private var tunnelState: TunnelState = .disconnected {
        didSet {
            setNeedsHeaderBarStyleAppearanceUpdate()
            updateSecureLabel()
            updateTunnelConnectionInfo()
        }
    }

    private var showedAccountView = false

    override func viewDidLoad() {
        super.viewDidLoad()

        addTileOverlay()
        loadGeoJSONData()
        hideMapsAttributions()

        connectionPanel.collapseButton.addTarget(self, action: #selector(handleConnectionPanelButton(_:)), for: .touchUpInside)

        tunnelStateSubscriber = TunnelManager.shared.$tunnelState
            .receive(on: DispatchQueue.main)
            .assign(to: \.tunnelState, on: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        showAccountViewForExpiredAccount()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if case .embedTunnelControls = SegueIdentifier.Connect.from(segue: segue) {
            let tunnelControlController = segue.destination as! TunnelControlViewController
            tunnelControlController.view.translatesAutoresizingMaskIntoConstraints = false
            tunnelControlController.delegate = self
        }
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polygon = overlay as? MKPolygon {
            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.shouldRasterize = true
            renderer.fillColor = UIColor.primaryColor
            renderer.strokeColor = UIColor.secondaryColor
            renderer.lineWidth = 1.0
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        if let multiPolygon = overlay as? MKMultiPolygon {
            let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
            renderer.shouldRasterize = true
            renderer.fillColor = UIColor.primaryColor
            renderer.strokeColor = UIColor.secondaryColor
            renderer.lineWidth = 1.0
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        if let tileOverlay = overlay as? MKTileOverlay {
            return CustomOverlayRenderer(overlay: tileOverlay)
        }

        return MKOverlayRenderer(overlay: overlay)
    }

    private func addTileOverlay() {
        // Use `nil` for template URL to make sure that Apple maps do not load
        // tiles from remote.
        let tileOverlay = MKTileOverlay(urlTemplate: nil)

        // Replace the default map tiles
        tileOverlay.canReplaceMapContent = true

        mapView.addOverlay(tileOverlay)
    }

    private func loadGeoJSONData() {
        let decoder = MKGeoJSONDecoder()

        let geoJSONURL = Bundle.main.url(forResource: "countries.geo", withExtension: "json")!

        let data = try! Data(contentsOf: geoJSONURL)
        let geoJSONObjects = try! decoder.decode(data)

        for object in geoJSONObjects {
            if let feat = object as? MKGeoJSONFeature {
                for case let overlay as MKOverlay in feat.geometry {
                    mapView.addOverlay(overlay, level: .aboveLabels)
                }
            }
        }
    }

    private func hideMapsAttributions() {
        let logoView = mapView.subviews.first { $0.description.starts(with: "<MKAppleLogoImageView") }
        let legalLink = mapView.subviews.first { $0.description.starts(with: "<MKAttributionLabel") }

        logoView?.isHidden = true
        legalLink?.isHidden = true
    }

    // MARK: - TunnelControlViewControllerDelegate

    func tunnelControlViewController(_ controller: TunnelControlViewController, handleAction action: TunnelControlAction) {
        switch action {
        case .connect:
            connectTunnel()

        case .disconnect:
            disconnectTunnel()

        case .selectLocation:
            performSegue(
                withIdentifier: SegueIdentifier.Connect.showRelaySelector.rawValue,
                sender: self)
        }
    }

    // MARK: - Private

    private func updateSecureLabel() {
        secureLabel.text = tunnelState.textForSecureLabel().uppercased()
        secureLabel.textColor = tunnelState.textColorForSecureLabel()
    }

    private func attributedStringForLocation(string: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.lineHeightMultiple = 0.80
        return NSAttributedString(string: string, attributes: [
            .paragraphStyle: paragraphStyle])
    }

    private func updateTunnelConnectionInfo() {
        switch tunnelState {
        case .connected(let connectionInfo),
             .reconnecting(let connectionInfo):
            cityLabel.attributedText = attributedStringForLocation(string: connectionInfo.location.city)
            countryLabel.attributedText = attributedStringForLocation(string: connectionInfo.location.country)

            connectionPanel.dataSource = ConnectionPanelData(
                inAddress: "\(connectionInfo.ipv4Relay) UDP",
                outAddress: nil
            )
            connectionPanel.isHidden = false
            connectionPanel.collapseButton.setTitle(connectionInfo.hostname, for: .normal)

        case .connecting, .disconnected, .disconnecting:
            cityLabel.attributedText = attributedStringForLocation(string: " ")
            countryLabel.attributedText = attributedStringForLocation(string: " ")
            connectionPanel.dataSource = nil
            connectionPanel.isHidden = true
        }
    }

    private func connectTunnel() {
        startStopTunnelSubscriber = TunnelManager.shared.startTunnel()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { (completion) in
                if case .failure(let error) = completion {
                    os_log(.error, "Failed to start the tunnel: %{public}s",
                           error.localizedDescription)

                    self.presentError(error, preferredStyle: .alert)
                }
            })
    }

    private func disconnectTunnel() {
        startStopTunnelSubscriber = TunnelManager.shared.stopTunnel()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { (completion) in
                if case .failure(let error) = completion {
                    os_log(.error, "Failed to stop the tunnel: %{public}s",
                           error.localizedDescription)

                    self.presentError(error, preferredStyle: .alert)
                }
            })
    }

    private func showAccountViewForExpiredAccount() {
        guard !showedAccountView else { return }

        showedAccountView = true

        if let accountExpiry = Account.shared.expiry, AccountExpiry(date: accountExpiry).isExpired {
            rootContainerController?.showSettings(navigateTo: .account, animated: true)
        }
    }

    // MARK: - Actions

    @objc func handleConnectionPanelButton(_ sender: Any) {
        connectionPanel.toggleConnectionInfoVisibility()
    }

    @IBAction func unwindFromSelectLocation(segue: UIStoryboardSegue) {
        guard let selectLocationController = segue.source as? SelectLocationController else { return }
        guard let selectedLocation = selectLocationController.selectedLocation else { return }

        let relayConstraints = RelayConstraints(location: .only(selectedLocation))

        setRelaysSubscriber = TunnelManager.shared.setRelayConstraints(relayConstraints)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { (completion) in
                switch completion {
                case .finished:
                    os_log(.debug, "Updated relay constraints: %{public}s", String(reflecting: relayConstraints))
                    self.connectTunnel()

                case .failure(let error):
                    os_log(.error, "Failed to update relay constraints: %{public}s", error.localizedDescription)
                }
            })
    }

}

private extension TunnelState {

    func textColorForSecureLabel() -> UIColor {
        switch self {
        case .connecting, .reconnecting:
            return .white

        case .connected:
            return .successColor

        case .disconnecting, .disconnected:
            return .dangerColor
        }
    }

    func textForSecureLabel() -> String {
        switch self {
        case .connecting, .reconnecting:
            return NSLocalizedString("Creating secure connection", comment: "")

        case .connected:
            return NSLocalizedString("Secure connection", comment: "")

        case .disconnecting, .disconnected:
            return NSLocalizedString("Unsecured connection", comment: "")
        }
    }

}
