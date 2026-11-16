#pragma once

#include <esp_http_server.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

#include <atomic>

#include "espiot/Pairing.h"
#include "espiot/Protocol.h"

// Keep one instance alive for the lifetime of the project. Run begin, poll,
// and end from the same task. Install controls before begin.
class EspIoT {
 public:
  struct TlsCredentials {
    const uint8_t* certificate = nullptr;
    size_t certificateLength = 0;
    const uint8_t* privateKey = nullptr;
    size_t privateKeyLength = 0;
  };
  EspIoT() = default;
  EspIoT(const EspIoT&) = delete;
  EspIoT& operator=(const EspIoT&) = delete;
  ~EspIoT();

  bool addSwitch(const char* id, const char* name, espiot::SwitchHandler handler,
                 void* context = nullptr, bool confirm = false) {
    return protocol_.addSwitch(id, name, handler, context, confirm);
  }
  bool addRange(const char* id, const char* name, double min, double max, double step,
                const char* unit, espiot::RangeHandler handler, void* context = nullptr,
                bool confirm = true) {
    return protocol_.addRange(id, name, min, max, step, unit, handler, context, confirm);
  }
  bool addSensor(const char* id, const char* name, const char* unit) {
    return protocol_.addSensor(id, name, unit);
  }
  bool addAction(const char* id, const char* name, espiot::ActionHandler handler,
                 void* context = nullptr, bool confirm = true) {
    return protocol_.addAction(id, name, handler, context, confirm);
  }
  bool addMotionStop(const char* id, const char* name, uint8_t directions, uint16_t maxDurationMs,
                     espiot::ActionHandler stop, void* context = nullptr) {
    return protocol_.addMotionStop(id, name, directions, maxDurationMs, stop, context);
  }

  bool publishSwitch(const char* id, bool value);
  bool publishNumber(const char* id, double value);
  bool publishUnavailable(const char* id);

  // Call once after Wi-Fi STA receives a private IPv4 address. poll retries
  // listener startup and recovers from subsequent Wi-Fi changes.
  bool begin(const char* name, const char* type, int32_t revision, uint16_t httpPort = 80,
             bool enableEvents = true);
  // The certificate and key buffers must outlive this instance's listeners.
  bool beginSecure(const char* name, const char* type, int32_t revision, TlsCredentials credentials,
                   uint16_t port = 443, bool enableEvents = true);
  bool openPairingWindow(char (&code)[9]);
  bool clearPairings();
  const char* certificateFingerprint() const { return fingerprint_; }
  void poll();
  void end();
  bool running() const { return server_ != nullptr; }
  const char* deviceId() const { return protocol_.deviceId(); }

 private:
  static esp_err_t authorizePeer(httpd_handle_t server, int socket);
  static esp_err_t descriptor(httpd_req_t* request);
  static esp_err_t status(httpd_req_t* request);
  static esp_err_t command(httpd_req_t* request);
  static esp_err_t pair(httpd_req_t* request);
  static esp_err_t revoke(httpd_req_t* request);
#ifdef CONFIG_HTTPD_WS_SUPPORT
  static esp_err_t events(httpd_req_t* request);
  static void publishEvents(void* context);
#if CONFIG_HTTPD_WS_PRE_HANDSHAKE_CB_SUPPORT
  static esp_err_t authorizeEvents(httpd_req_t* request);
#endif
#endif
  bool localPeer(int socket) const;
  bool linkMatches() const;
  bool startNetwork(uint32_t address, uint32_t mask);
  void stopNetwork();
  void pollDiscovery(uint32_t now);
  bool beginInternal(const char* name, const char* type, int32_t revision, uint16_t port,
                     bool enableEvents, TlsCredentials credentials);
  bool secure() const { return tls_.certificate != nullptr; }
  uint32_t principal(httpd_req_t* request) const;
  static bool savePairings(void* context, const espiot::TokenDigest* entries);

  espiot::Protocol protocol_;
  espiot::PairingWindow pairingWindow_;
  espiot::TokenLedger tokens_;
  TlsCredentials tls_;
  char fingerprint_[65]{};
  SemaphoreHandle_t lock_ = nullptr;
  char* reply_ = nullptr;
  httpd_handle_t server_ = nullptr;
  int udp_ = -1;
  uint32_t address_ = 0, mask_ = 0;
  uint16_t port_ = 0;
  uint32_t lastStart_ = 0, lastOffer_ = 0, lastEvent_ = 0;
  bool enabled_ = false, mdnsOwned_ = false, mdnsService_ = false;
#ifdef CONFIG_HTTPD_WS_SUPPORT
  struct Subscriber {
    int fd = -1;
    uint32_t principal = 0;
  };
  Subscriber subscribers_[3]{};
  std::atomic<bool> eventQueued_{false};
#endif
};
