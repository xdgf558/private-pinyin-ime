#pragma once

namespace private_pinyin {

template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  explicit ComPtr(T* value) : value_(value) {}

  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  ComPtr(ComPtr&& other) noexcept : value_(other.value_) {
    other.value_ = nullptr;
  }

  ComPtr& operator=(ComPtr&& other) noexcept {
    if (this != &other) {
      reset();
      value_ = other.value_;
      other.value_ = nullptr;
    }
    return *this;
  }

  ~ComPtr() {
    reset();
  }

  T* get() const {
    return value_;
  }

  T** put() {
    reset();
    return &value_;
  }

  T* operator->() const {
    return value_;
  }

  explicit operator bool() const {
    return value_ != nullptr;
  }

  T* detach() {
    T* value = value_;
    value_ = nullptr;
    return value;
  }

  void reset(T* value = nullptr) {
    if (value_ != nullptr) {
      value_->Release();
    }
    value_ = value;
  }

 private:
  T* value_ = nullptr;
};

}  // namespace private_pinyin
