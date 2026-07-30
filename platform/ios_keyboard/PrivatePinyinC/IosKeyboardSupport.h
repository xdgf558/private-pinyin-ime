#ifndef PRIVATE_PINYIN_IOS_KEYBOARD_SUPPORT_H
#define PRIVATE_PINYIN_IOS_KEYBOARD_SUPPORT_H

#include <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// UIKit does not annotate UITextDocumentProxy.documentIdentifier as nullable,
// but some hosts return nil while attaching or replacing a document. Returning
// it through an explicitly nullable Objective-C boundary prevents Swift from
// trapping in UUID._unconditionallyBridgeFromObjectiveC.
static inline NSUUID * _Nullable private_pinyin_ios_document_identifier(
    id<UITextDocumentProxy> proxy) {
  return proxy.documentIdentifier;
}

NS_ASSUME_NONNULL_END
#endif

#endif
