set(espiot_src "${CMAKE_CURRENT_LIST_DIR}/../../arduino/EspIoT/src")

idf_component_register(
  SRCS "${espiot_src}/EspIoT.cpp" "${espiot_src}/espiot/Protocol.cpp" "${espiot_src}/espiot/Wire.cpp" "${espiot_src}/espiot/Pairing.cpp"
  INCLUDE_DIRS "${espiot_src}"
  REQUIRES esp_http_server freertos
  PRIV_REQUIRES esp_netif esp_timer esp_hw_support lwip nvs_flash esp_https_server mbedtls
)

target_compile_features(${COMPONENT_LIB} PRIVATE cxx_std_17)
