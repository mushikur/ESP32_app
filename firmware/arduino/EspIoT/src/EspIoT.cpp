#include "EspIoT.h"

#include <esp_https_server.h>
#include <esp_netif.h>
#include <esp_random.h>
#include <esp_timer.h>
#include <lwip/sockets.h>
#include <mbedtls/sha256.h>
#include <mbedtls/x509_crt.h>
#include <mdns.h>
#include <nvs.h>

#include <cstdio>
#include <cstring>
#include <new>

#include "espiot/Wire.h"

namespace {

constexpr uint16_t discoveryPort = 55073;
constexpr uint32_t retryInterval = 1500;
constexpr uint32_t eventInterval = 2000;
constexpr uint32_t offerInterval = 125;

uint64_t securityTime() { return static_cast<uint64_t>(esp_timer_get_time() / 1000); }
uint32_t milliseconds() { return static_cast<uint32_t>(securityTime()); }

class StateLock {
 public:
  explicit StateLock(SemaphoreHandle_t lock) : lock_(lock) {
    if (lock_) xSemaphoreTake(lock_, portMAX_DELAY);
  }
  ~StateLock() {
    if (lock_) xSemaphoreGive(lock_);
  }

 private:
  SemaphoreHandle_t lock_;
};

bool privateIpv4(uint32_t address) {
  return (address >> 24) == 10 || (address >> 20) == 0xac1 || (address >> 16) == 0xc0a8;
}

bool stationScope(uint32_t& address, uint32_t& mask) {
  auto* sta = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  esp_netif_ip_info_t ip{};
  if (!sta || !esp_netif_is_netif_up(sta) || esp_netif_get_ip_info(sta, &ip) != ESP_OK)
    return false;
  address = ntohl(ip.ip.addr);
  mask = ntohl(ip.netmask.addr);
  const uint32_t hostBits = ~mask;
  const uint32_t first = address & mask;
  const uint32_t last = first | hostBits;
  return mask >= 0xff000000UL && hostBits >= 3 && !(hostBits & (hostBits + 1)) &&
         privateIpv4(first) && privateIpv4(last) && address > first && address < last;
}

bool sameSubnetPeer(uint32_t address, uint32_t mask, uint32_t source) {
  const uint32_t first = address & mask;
  return source != address && source > first && source < (first | ~mask);
}

uint32_t ipv4(const sockaddr_storage& address) {
  if (address.ss_family == AF_INET) {
    return ntohl(reinterpret_cast<const sockaddr_in&>(address).sin_addr.s_addr);
  }
#if CONFIG_LWIP_IPV6
  if (address.ss_family == AF_INET6) {
    const auto& mapped = reinterpret_cast<const sockaddr_in6&>(address).sin6_addr;
    constexpr uint8_t prefix[12] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff};
    if (std::memcmp(mapped.s6_addr, prefix, sizeof(prefix)) == 0) {
      uint32_t value;
      std::memcpy(&value, mapped.s6_addr + 12, sizeof(value));
      return ntohl(value);
    }
  }
#endif
  return 0;
}

void hexBytes(const uint8_t* bytes, size_t size, char* output) {
  const char hex[] = "0123456789abcdef";
  for (size_t index = 0; index < size; ++index) {
    output[index * 2] = hex[bytes[index] >> 4];
    output[index * 2 + 1] = hex[bytes[index] & 15];
  }
  output[size * 2] = '\0';
}

template <size_t N>
void randomHex(char (&output)[N]) {
  uint8_t bytes[(N - 1) / 2];
  esp_fill_random(bytes, sizeof(bytes));
  hexBytes(bytes, sizeof(bytes), output);
}

bool digest(const uint8_t* input, size_t length, espiot::TokenDigest& output) {
  return mbedtls_sha256(input, length, output.bytes, 0) == 0;
}

bool fingerprint(EspIoT::TlsCredentials tls, char (&output)[65]) {
  mbedtls_x509_crt certificate;
  mbedtls_x509_crt_init(&certificate);
  espiot::TokenDigest hash;
  const bool valid =
      mbedtls_x509_crt_parse(&certificate, tls.certificate, tls.certificateLength) == 0 &&
      certificate.raw.p && digest(certificate.raw.p, certificate.raw.len, hash);
  if (valid) hexBytes(hash.bytes, sizeof(hash.bytes), output);
  mbedtls_x509_crt_free(&certificate);
  return valid;
}

struct StoredPairings {
  char deviceId[33]{};
  espiot::TokenDigest tokens[espiot::TokenLedger::capacity]{};
};

bool loadPairings(const char* id, espiot::TokenLedger& ledger) {
  nvs_handle_t handle;
  if (nvs_open("esp_iot", NVS_READWRITE, &handle) != ESP_OK) return false;
  StoredPairings stored;
  size_t size = sizeof(stored);
  const esp_err_t result = nvs_get_blob(handle, "token_hashes", &stored, &size);
  nvs_close(handle);
  if (result == ESP_ERR_NVS_NOT_FOUND) return true;
  if (result != ESP_OK || size != sizeof(stored)) return false;
  return std::memcmp(stored.deviceId, id, sizeof(stored.deviceId)) != 0 ||
         ledger.load(stored.tokens);
}

bool loadIdentity(char (&id)[33]) {
  nvs_handle_t handle;
  if (nvs_open("esp_iot", NVS_READWRITE, &handle) != ESP_OK) return false;
  size_t size = sizeof(id);
  esp_err_t result = nvs_get_str(handle, "device_id", id, &size);
  if (result == ESP_ERR_NVS_NOT_FOUND) {
    randomHex(id);
    result = nvs_set_str(handle, "device_id", id);
    if (result == ESP_OK) result = nvs_commit(handle);
  }
  nvs_close(handle);
  return result == ESP_OK && espiot::hexId(id);
}

const char* statusLine(unsigned status) {
  switch (status) {
    case 200:
      return "200 OK";
    case 204:
      return "204 No Content";
    case 400:
      return "400 Bad Request";
    case 401:
      return "401 Unauthorized";
    case 403:
      return "403 Forbidden";
    case 409:
      return "409 Conflict";
    case 413:
      return "413 Content Too Large";
    case 415:
      return "415 Unsupported Media Type";
    case 429:
      return "429 Too Many Requests";
    default:
      return "500 Internal Server Error";
  }
}

esp_err_t sendJson(httpd_req_t* request, unsigned status, const char* bytes, size_t size) {
  if (!size)
    return httpd_resp_send_err(request, HTTPD_500_INTERNAL_SERVER_ERROR, "Response unavailable");
  httpd_resp_set_status(request, statusLine(status));
  httpd_resp_set_type(request, "application/json");
  httpd_resp_set_hdr(request, "Cache-Control", "no-store");
  if (status == 401) httpd_resp_set_hdr(request, "WWW-Authenticate", "Bearer");
  return httpd_resp_send(request, bytes, size);
}

esp_err_t closeWithError(httpd_req_t* request, unsigned status, const char* body) {
  httpd_resp_set_hdr(request, "Connection", "close");
  sendJson(request, status, body, std::strlen(body));
  return ESP_FAIL;
}

bool jsonRequest(httpd_req_t* request) {
  char type[64];
  if (httpd_req_get_hdr_value_str(request, "Content-Type", type, sizeof(type)) != ESP_OK)
    return false;
  char* end = std::strchr(type, ';');
  if (!end) end = type + std::strlen(type);
  while (end > type && (end[-1] == ' ' || end[-1] == '\t')) --end;
  *end = '\0';
  return strcasecmp(type, "application/json") == 0;
}

bool readBody(httpd_req_t* request, char* input) {
  size_t used = 0;
  const uint32_t start = milliseconds();
  while (used < request->content_len) {
    const int count = httpd_req_recv(request, input + used, request->content_len - used);
    if (count <= 0 || milliseconds() - start > 1500) return false;
    used += count;
  }
  return true;
}

}  // namespace

EspIoT::~EspIoT() {
  end();
  if (lock_) vSemaphoreDelete(lock_);
  delete[] reply_;
}

bool EspIoT::publishSwitch(const char* id, bool value) {
  StateLock guard(lock_);
  return protocol_.publishSwitch(id, value);
}

bool EspIoT::publishNumber(const char* id, double value) {
  StateLock guard(lock_);
  return protocol_.publishNumber(id, value);
}

bool EspIoT::publishUnavailable(const char* id) {
  StateLock guard(lock_);
  return protocol_.publishUnavailable(id);
}

bool EspIoT::begin(const char* name, const char* type, int32_t revision, uint16_t httpPort,
                   bool enableEvents) {
  return beginInternal(name, type, revision, httpPort, enableEvents, {});
}

bool EspIoT::beginSecure(const char* name, const char* type, int32_t revision,
                         TlsCredentials credentials, uint16_t port, bool enableEvents) {
#if CONFIG_ESP_HTTPS_SERVER_ENABLE
#if !CONFIG_HTTPD_WS_PRE_HANDSHAKE_CB_SUPPORT
  enableEvents = false;
#endif
  if (!credentials.certificate || !credentials.privateKey || !credentials.certificateLength ||
      !credentials.privateKeyLength || credentials.certificateLength > 8192 ||
      credentials.privateKeyLength > 8192)
    return false;
  return beginInternal(name, type, revision, port, enableEvents, credentials);
#else
  return false;
#endif
}

bool EspIoT::beginInternal(const char* name, const char* type, int32_t revision, uint16_t httpPort,
                           bool enableEvents, TlsCredentials credentials) {
  uint32_t address = 0, mask = 0;
  if (port_ || !httpPort || !stationScope(address, mask) || !espiot::label(name, 64) ||
      !espiot::capabilityId(type) || revision < 1)
    return false;
  char id[33]{}, boot[33]{};
  if (!loadIdentity(id)) return false;
  const bool pairing = credentials.certificate != nullptr;
  if (pairing && !fingerprint(credentials, fingerprint_)) return false;
  randomHex(boot);
  auto* buffer = new (std::nothrow) char[espiot::Protocol::outputCapacity];
  if (!buffer) return false;
  const auto lock = xSemaphoreCreateMutex();
  if (!lock) {
    delete[] buffer;
    return false;
  }
#ifndef CONFIG_HTTPD_WS_SUPPORT
  enableEvents = false;
#endif
  if ((pairing && !loadPairings(id, tokens_)) ||
      !protocol_.configure(name, type, revision, id, boot, enableEvents, pairing)) {
    vSemaphoreDelete(lock);
    delete[] buffer;
    return false;
  }
  reply_ = buffer;
  lock_ = lock;
  tls_ = credentials;
  port_ = httpPort;
  enabled_ = true;
  lastStart_ = milliseconds() - retryInterval;
  poll();
  return true;
}

bool EspIoT::openPairingWindow(char (&code)[9]) {
  code[0] = 0;
  if (!secure() || !running() || !linkMatches()) return false;
  StateLock guard(lock_);
  if (tokens_.full()) return false;
  uint32_t value;
  do {
    value = esp_random();
  } while (value >= 4200000000UL);
  std::snprintf(code, sizeof(code), "%08lu", static_cast<unsigned long>(value % 100000000UL));
  return pairingWindow_.open(code, securityTime());
}

bool EspIoT::clearPairings() {
  if (!secure()) return false;
  StateLock guard(lock_);
  pairingWindow_.close();
  return tokens_.clear(savePairings, this);
}

bool EspIoT::savePairings(void* context, const espiot::TokenDigest* entries) {
  auto* self = static_cast<EspIoT*>(context);
  nvs_handle_t handle;
  if (nvs_open("esp_iot", NVS_READWRITE, &handle) != ESP_OK) return false;
  StoredPairings stored;
  std::memcpy(stored.deviceId, self->deviceId(), sizeof(stored.deviceId));
  std::memcpy(stored.tokens, entries, sizeof(stored.tokens));
  esp_err_t result = nvs_set_blob(handle, "token_hashes", &stored, sizeof(stored));
  if (result == ESP_OK) result = nvs_commit(handle);
  nvs_close(handle);
  return result == ESP_OK;
}

uint32_t EspIoT::principal(httpd_req_t* request) const {
  constexpr char prefix[] = "Bearer ";
  char authorization[72]{};
  if (httpd_req_get_hdr_value_len(request, "Authorization") != sizeof(authorization) - 1 ||
      httpd_req_get_hdr_value_str(request, "Authorization", authorization, sizeof(authorization)) !=
          ESP_OK ||
      std::memcmp(authorization, prefix, sizeof(prefix) - 1) != 0)
    return 0;
  const char* token = authorization + sizeof(prefix) - 1;
  for (size_t index = 0; index < 64; ++index) {
    if (!(token[index] >= '0' && token[index] <= '9') &&
        !(token[index] >= 'a' && token[index] <= 'f'))
      return 0;
  }
  espiot::TokenDigest hash;
  return digest(reinterpret_cast<const uint8_t*>(token), 64, hash) ? tokens_.principal(hash) : 0;
}

void EspIoT::end() {
  enabled_ = false;
  stopNetwork();
}

void EspIoT::poll() {
  if (!enabled_) return;
  const uint32_t now = milliseconds();
  uint32_t address = 0, mask = 0;
  const bool active = stationScope(address, mask);
  if (server_ && (!active || address != address_ || mask != mask_)) {
    stopNetwork();
    lastStart_ = now - retryInterval;
  }
  if (!server_) {
    if (!active || now - lastStart_ < retryInterval) return;
    lastStart_ = now;
    if (!startNetwork(address, mask)) return;
  }
  pollDiscovery(now);
#ifdef CONFIG_HTTPD_WS_SUPPORT
  if (protocol_.events() && now - lastEvent_ >= eventInterval) {
    lastEvent_ = now;
    if (!eventQueued_.exchange(true) && httpd_queue_work(server_, publishEvents, this) != ESP_OK) {
      eventQueued_.store(false);
    }
  }
#endif
}

bool EspIoT::startNetwork(uint32_t address, uint32_t mask) {
  address_ = address;
  mask_ = mask;
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = port_;
  config.ctrl_port = 32770;
  config.max_uri_handlers = 6;
  config.max_open_sockets = 6;
  config.stack_size = 8192;
  config.recv_wait_timeout = 1;
  config.send_wait_timeout = 1;
  config.lru_purge_enable = true;
  config.global_user_ctx = this;
  config.global_user_ctx_free_fn = [](void*) {};
  config.open_fn = authorizePeer;
  httpd_handle_t started = nullptr;
  if (secure()) {
#if CONFIG_ESP_HTTPS_SERVER_ENABLE
    httpd_ssl_config_t ssl = HTTPD_SSL_CONFIG_DEFAULT();
    ssl.httpd = config;
    ssl.httpd.open_fn = nullptr;
    ssl.httpd.stack_size = 12288;
    ssl.httpd.max_open_sockets = 3;
    ssl.port_secure = port_;
    ssl.servercert = tls_.certificate;
    ssl.servercert_len = tls_.certificateLength;
    ssl.prvtkey_pem = tls_.privateKey;
    ssl.prvtkey_len = tls_.privateKeyLength;
    ssl.tls_handshake_timeout_ms = 2000;
    if (httpd_ssl_start(&started, &ssl) != ESP_OK) return false;
#else
    return false;
#endif
  } else if (httpd_start(&started, &config) != ESP_OK)
    return false;
  server_ = started;

  httpd_uri_t routes[6]{};
  routes[0].uri = "/.well-known/esp-iot";
  routes[0].handler = descriptor;
  routes[1].uri = "/api/v1/status";
  routes[1].handler = status;
  routes[2].uri = "/api/v1/commands";
  routes[2].handler = command;
  routes[0].method = routes[1].method = HTTP_GET;
  routes[2].method = HTTP_POST;
  size_t routeCount = 3;
#ifdef CONFIG_HTTPD_WS_SUPPORT
  if (protocol_.events()) {
    auto& route = routes[routeCount++];
    route.uri = "/api/v1/events";
    route.handler = events;
    route.method = HTTP_GET;
    route.is_websocket = true;
#if CONFIG_HTTPD_WS_PRE_HANDSHAKE_CB_SUPPORT
    route.ws_pre_handshake_cb = authorizeEvents;
#endif
  }
#endif
  if (secure()) {
    auto& enrollment = routes[routeCount++];
    enrollment.uri = "/api/v1/pair";
    enrollment.method = HTTP_POST;
    enrollment.handler = pair;
    auto& removal = routes[routeCount++];
    removal.uri = "/api/v1/pairing";
    removal.method = HTTP_DELETE;
    removal.handler = revoke;
  }
  for (size_t index = 0; index < routeCount; ++index) {
    routes[index].user_ctx = this;
    if (httpd_register_uri_handler(server_, &routes[index]) != ESP_OK) {
      stopNetwork();
      return false;
    }
  }

  udp_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (udp_ >= 0) {
    const int allowBroadcast = 1;
    setsockopt(udp_, SOL_SOCKET, SO_BROADCAST, &allowBroadcast, sizeof(allowBroadcast));
    sockaddr_in destination{};
    destination.sin_family = AF_INET;
    destination.sin_port = htons(discoveryPort);
    destination.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(udp_, reinterpret_cast<sockaddr*>(&destination), sizeof(destination)) < 0) {
      close(udp_);
      udp_ = -1;
    }
  }

  char hostname[MDNS_NAME_BUF_LEN]{};
  const esp_err_t hostnameResult = mdns_hostname_get(hostname);
  if (hostnameResult == ESP_ERR_INVALID_STATE) mdnsOwned_ = mdns_init() == ESP_OK;
  bool canAdvertise = mdnsOwned_ || hostnameResult == ESP_OK;
  if (canAdvertise && !hostname[0]) {
    std::snprintf(hostname, sizeof(hostname), "espiot-%.12s", protocol_.deviceId());
    canAdvertise = mdns_hostname_set(hostname) == ESP_OK;
  }
  if (canAdvertise && !mdns_service_exists("_espiot", "_tcp", nullptr)) {
    mdns_txt_item_t txt[] = {
        {"v", "1"}, {"id", protocol_.deviceId()}, {"tls", secure() ? "1" : "0"}};
    mdnsService_ = mdns_service_add(nullptr, "_espiot", "_tcp", port_, txt, 3) == ESP_OK;
  }
  lastOffer_ = milliseconds() - offerInterval;
  lastEvent_ = milliseconds() - eventInterval;
  return true;
}

void EspIoT::stopNetwork() {
  if (lock_) {
    StateLock guard(lock_);
    pairingWindow_.close();
  }
  if (mdnsService_) mdns_service_remove("_espiot", "_tcp");
  if (mdnsOwned_) mdns_free();
  mdnsService_ = mdnsOwned_ = false;
  if (udp_ >= 0) {
    close(udp_);
    udp_ = -1;
  }
  if (server_) {
#if CONFIG_ESP_HTTPS_SERVER_ENABLE
    if (secure())
      httpd_ssl_stop(server_);
    else
#endif
      httpd_stop(server_);
    server_ = nullptr;
  }
#ifdef CONFIG_HTTPD_WS_SUPPORT
  for (auto& subscriber : subscribers_) subscriber = {};
  eventQueued_.store(false);
#endif
}

void EspIoT::pollDiscovery(uint32_t now) {
  if (udp_ < 0 || now - lastOffer_ < offerInterval) return;
  for (int attempt = 0; attempt < 4; ++attempt) {
    char input[espiot::Protocol::maxDiscoveryBytes + 1];
    sockaddr_in peer{};
    socklen_t length = sizeof(peer);
    const int count = recvfrom(udp_, input, sizeof(input), MSG_DONTWAIT,
                               reinterpret_cast<sockaddr*>(&peer), &length);
    if (count <= 0) return;
    if (peer.sin_family != AF_INET || !peer.sin_port ||
        !sameSubnetPeer(address_, mask_, ntohl(peer.sin_addr.s_addr)))
      continue;
    char output[espiot::Protocol::maxDiscoveryBytes];
    const size_t size = protocol_.offer(input, count, port_, output, sizeof(output));
    if (!size) continue;
    lastOffer_ = now;
    sendto(udp_, output, size, MSG_DONTWAIT, reinterpret_cast<sockaddr*>(&peer), length);
    return;
  }
}

bool EspIoT::linkMatches() const {
  uint32_t address = 0, mask = 0;
  return stationScope(address, mask) && address == address_ && mask == mask_;
}

bool EspIoT::localPeer(int fd) const {
  sockaddr_storage peer{}, local{};
  socklen_t peerSize = sizeof(peer), localSize = sizeof(local);
  return getpeername(fd, reinterpret_cast<sockaddr*>(&peer), &peerSize) == 0 &&
         getsockname(fd, reinterpret_cast<sockaddr*>(&local), &localSize) == 0 &&
         ipv4(local) == address_ && sameSubnetPeer(address_, mask_, ipv4(peer)) && linkMatches();
}

esp_err_t EspIoT::authorizePeer(httpd_handle_t server, int fd) {
  auto* self = static_cast<EspIoT*>(httpd_get_global_user_ctx(server));
  return self->localPeer(fd) ? ESP_OK : ESP_FAIL;
}

esp_err_t EspIoT::descriptor(httpd_req_t* request) {
  auto* self = static_cast<EspIoT*>(request->user_ctx);
  if (!self->localPeer(httpd_req_to_sockfd(request))) return ESP_FAIL;
  const size_t length = self->protocol_.descriptor(self->reply_, espiot::Protocol::outputCapacity);
  return sendJson(request, 200, self->reply_, length);
}

esp_err_t EspIoT::status(httpd_req_t* request) {
  auto* self = static_cast<EspIoT*>(request->user_ctx);
  if (!self->localPeer(httpd_req_to_sockfd(request))) return ESP_FAIL;
  size_t length;
  {
    StateLock guard(self->lock_);
    if (self->secure() && !self->principal(request))
      return closeWithError(request, 401, "{\"code\":\"auth_required\"}");
    length = self->protocol_.snapshot(self->reply_, espiot::Protocol::outputCapacity);
  }
  return sendJson(request, 200, self->reply_, length);
}

esp_err_t EspIoT::command(httpd_req_t* request) {
  auto* self = static_cast<EspIoT*>(request->user_ctx);
  if (!self->localPeer(httpd_req_to_sockfd(request))) return ESP_FAIL;
  if (httpd_req_get_hdr_value_len(request, "Origin")) {
    return closeWithError(request, 403, "{\"code\":\"forbidden\"}");
  }
  if (!jsonRequest(request))
    return closeWithError(request, 415, "{\"code\":\"invalid_content_type\"}");
  if (request->content_len > espiot::Protocol::maxCommandBytes) {
    return closeWithError(request, 413, "{\"code\":\"command_too_large\"}");
  }
  char input[espiot::Protocol::maxCommandBytes];
  if (!readBody(request, input)) return ESP_FAIL;
  if (!self->linkMatches()) return ESP_FAIL;
  espiot::Reply reply;
  {
    StateLock guard(self->lock_);
    const uint32_t principal = self->secure() ? self->principal(request) : 0;
    reply = self->protocol_.command(input, request->content_len, securityTime(), self->reply_,
                                    espiot::Protocol::outputCapacity, principal);
  }
  return sendJson(request, reply.status, self->reply_, reply.size);
}

esp_err_t EspIoT::pair(httpd_req_t* request) {
  auto* self = static_cast<EspIoT*>(request->user_ctx);
  if (!self->secure() || !self->localPeer(httpd_req_to_sockfd(request))) return ESP_FAIL;
  if (httpd_req_get_hdr_value_len(request, "Origin"))
    return closeWithError(request, 403, "{\"code\":\"forbidden\"}");
  if (!jsonRequest(request))
    return closeWithError(request, 415, "{\"code\":\"invalid_content_type\"}");
  char input[128];
  if (request->content_len > sizeof(input))
    return closeWithError(request, 413, "{\"code\":\"command_too_large\"}");
  if (!readBody(request, input) || !self->linkMatches()) return ESP_FAIL;
  espiot::WireObject body;
  const char* id = nullptr;
  if (body.parse(input, request->content_len) && body.count() == 2) id = body.string("deviceId");
  if (!id || std::strcmp(id, self->deviceId()) != 0)
    return closeWithError(request, 400, "{\"code\":\"invalid_pairing\"}");

  char token[65]{};
  {
    StateLock guard(self->lock_);
    if (self->tokens_.full()) return closeWithError(request, 429, "{\"code\":\"busy\"}");
    const auto attempt = self->pairingWindow_.check(body.string("code"), securityTime());
    if (attempt == espiot::PairingAttempt::busy)
      return closeWithError(request, 429, "{\"code\":\"busy\"}");
    if (attempt != espiot::PairingAttempt::accepted)
      return closeWithError(request, 401, "{\"code\":\"auth_required\"}");
    randomHex(token);
    espiot::TokenDigest hash;
    if (!digest(reinterpret_cast<const uint8_t*>(token), 64, hash) ||
        !self->tokens_.issue(hash, savePairings, self)) {
      return closeWithError(request, 500, "{\"code\":\"storage_error\"}");
    }
  }
  char response[192];
  espiot::JsonWriter writer(response, sizeof(response));
  writer.raw("{\"deviceId\":");
  writer.string(self->deviceId());
  writer.raw(",\"token\":");
  writer.string(token);
  writer.raw("}");
  return sendJson(request, 200, response, writer.size());
}

esp_err_t EspIoT::revoke(httpd_req_t* request) {
  auto* self = static_cast<EspIoT*>(request->user_ctx);
  if (!self->secure() || !self->localPeer(httpd_req_to_sockfd(request))) return ESP_FAIL;
  if (httpd_req_get_hdr_value_len(request, "Origin") || request->content_len) {
    return closeWithError(request, 403, "{\"code\":\"forbidden\"}");
  }
  {
    StateLock guard(self->lock_);
    const uint32_t principal = self->principal(request);
    if (!principal) return closeWithError(request, 401, "{\"code\":\"auth_required\"}");
    if (!self->tokens_.revoke(principal, savePairings, self))
      return closeWithError(request, 500, "{\"code\":\"storage_error\"}");
  }
  httpd_resp_set_status(request, statusLine(204));
  httpd_resp_set_hdr(request, "Cache-Control", "no-store");
  return httpd_resp_send(request, nullptr, 0);
}

#ifdef CONFIG_HTTPD_WS_SUPPORT
#if CONFIG_HTTPD_WS_PRE_HANDSHAKE_CB_SUPPORT
esp_err_t EspIoT::authorizeEvents(httpd_req_t* request) {
  auto* self = static_cast<EspIoT*>(httpd_get_global_user_ctx(request->handle));
  if (!self->localPeer(httpd_req_to_sockfd(request))) return ESP_FAIL;
  StateLock guard(self->lock_);
  if (self->secure() && !self->principal(request))
    return closeWithError(request, 401, "{\"code\":\"auth_required\"}");
  return ESP_OK;
}
#endif

esp_err_t EspIoT::events(httpd_req_t* request) {
  auto* self = static_cast<EspIoT*>(request->user_ctx);
  // ESP HTTP Server handles control frames. Application data is device-to-app only.
  if (request->method != HTTP_GET || !self->localPeer(httpd_req_to_sockfd(request)))
    return ESP_FAIL;
  const int fd = httpd_req_to_sockfd(request);
  for (auto& subscriber : self->subscribers_) {
    if (subscriber.fd == fd ||
        (subscriber.fd >= 0 &&
         httpd_ws_get_fd_info(request->handle, subscriber.fd) != HTTPD_WS_CLIENT_WEBSOCKET)) {
      subscriber = {};
    }
  }
  const size_t limit =
      self->secure() ? 1 : sizeof(self->subscribers_) / sizeof(self->subscribers_[0]);
  for (size_t index = 0; index < limit; ++index) {
    auto& subscriber = self->subscribers_[index];
    if (subscriber.fd >= 0) continue;
    size_t length;
    uint32_t principal = 0;
    {
      StateLock guard(self->lock_);
      if (self->secure() && !(principal = self->principal(request))) return ESP_FAIL;
      length = self->protocol_.snapshot(self->reply_, espiot::Protocol::outputCapacity);
    }
    if (!length) return ESP_FAIL;
    httpd_ws_frame_t frame{};
    frame.type = HTTPD_WS_TYPE_TEXT;
    frame.payload = reinterpret_cast<uint8_t*>(self->reply_);
    frame.len = length;
    if (httpd_ws_send_frame(request, &frame) != ESP_OK) return ESP_FAIL;
    subscriber = {fd, principal};
    return ESP_OK;
  }
  return ESP_FAIL;
}

void EspIoT::publishEvents(void* context) {
  auto* self = static_cast<EspIoT*>(context);
  httpd_ws_frame_t frame{};
  frame.type = HTTPD_WS_TYPE_TEXT;
  frame.payload = reinterpret_cast<uint8_t*>(self->reply_);
  if (self->linkMatches()) {
    for (auto& subscriber : self->subscribers_) {
      const int fd = subscriber.fd;
      if (fd < 0) continue;
      if (httpd_ws_get_fd_info(self->server_, fd) != HTTPD_WS_CLIENT_WEBSOCKET) {
        subscriber = {};
        continue;
      }
      if (self->secure()) {
        StateLock guard(self->lock_);
        if (!self->tokens_.hasPrincipal(subscriber.principal)) {
          httpd_sess_trigger_close(self->server_, fd);
          subscriber = {};
          continue;
        }
      }
      if (!frame.len) {
        StateLock guard(self->lock_);
        frame.len = self->protocol_.snapshot(self->reply_, espiot::Protocol::outputCapacity);
      }
      if (!frame.len || httpd_ws_send_frame_async(self->server_, fd, &frame) != ESP_OK) {
        httpd_sess_trigger_close(self->server_, fd);
        subscriber = {};
      }
    }
  }
  self->eventQueued_.store(false);
}
#endif
