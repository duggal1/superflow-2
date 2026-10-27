//! Minimal C ABI around `harper-core`.
//!
//! # Offset contract
//!
//! Every `start`/`length` pair returned by [`harper_linter_lint`] is measured in
//! **UTF-16 code units**, not bytes and not Unicode scalar values. That is the
//! unit `NSRange`, `NSAttributedString` and `String.utf16` use on the Swift side,
//! so callers never have to convert. `byte_len` is the length of the UTF-8
//! buffer in bytes.
//!
//! The Rust side keeps char indices (Harper's span unit) internally and maps
//! them to UTF-16 offsets before returning. Emoji (two UTF-16 units) and CJK
//! (one UTF-16 unit per scalar) are covered by the unit tests at the bottom of
//! this file.
//!
//! # Ownership
//!
//! * `harper_linter_create` returns an owned pointer; release it with
//!   `harper_linter_free`.
//! * `harper_linter_lint` returns an owned array of [`HarperLintC`]; release it
//!   with `harper_lints_free(lints, count)`. Every non-null `kind`, `message`
//!   and `suggestion` string is owned by the array and freed with it.
//! * A `NULL` `suggestion` means "no suggestion"; an empty suggestion is
//!   represented by `has_suggestion == 0` as well. `has_suggestion == 1` with a
//!   non-null pointer means the caller may apply it (a removal is an empty
//!   string, which is why the flag exists).

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;

use harper_core::linting::{LintGroup, Linter as _, Suggestion};
use harper_core::spell::{FstDictionary, MutableDictionary};
use harper_core::{Dialect, DialectFlags, DictWordMetadata, Document};

/// One lint crossing the FFI boundary.
///
/// `start` and `length` are UTF-16 code units. `kind`, `message` and
/// `suggestion` are null-terminated UTF-8 strings owned by the array.
#[repr(C)]
pub struct HarperLintC {
    pub start: i32,
    pub length: i32,
    pub kind: *const c_char,
    pub message: *const c_char,
    pub suggestion: *const c_char,
    pub has_suggestion: i32,
}

pub struct HarperLinter {
    dialect: Dialect,
    custom_words: Vec<String>,
    dictionary: Option<Arc<FstDictionary>>,
    group: Option<LintGroup>,
    dirty: bool,
}

fn metadata(dialect: Dialect) -> DictWordMetadata {
    DictWordMetadata {
        noun: None,
        pronoun: None,
        verb: None,
        adjective: None,
        adverb: None,
        conjunction: None,
        determiner: None,
        affix: None,
        preposition: false,
        swear: None,
        abbreviation: None,
        dialects: DialectFlags::from_dialect(dialect),
        orth_info: Default::default(),
        common: false,
        derived_from: None,
        np_member: None,
        pos_tag: None,
    }
}

fn build_dictionary(custom_words: &[String], dialect: Dialect) -> Arc<FstDictionary> {
    let mut mutable = (*MutableDictionary::curated()).clone();
    for word in custom_words {
        if !word.is_empty() {
            mutable.append_word_str(word, metadata(dialect));
        }
    }
    Arc::new(mutable.into())
}

/// Maps char indices (Harper's span unit) to UTF-16 offsets.
fn utf16_offsets(text: &str) -> Vec<usize> {
    let mut offsets = Vec::with_capacity(text.chars().count() + 1);
    offsets.push(0);
    let mut total = 0usize;
    for ch in text.chars() {
        total += ch.len_utf16();
        offsets.push(total);
    }
    offsets
}

fn owned_c_string(value: &str) -> *const c_char {
    CString::new(value)
        .map(|c| c.into_raw() as *const c_char)
        .unwrap_or(std::ptr::null())
}

/// Creates a linter for a dialect name (`american`, `british`, `canadian`,
/// `australian`, `indian`). Unknown names fall back to American.
///
/// Returns null only if allocation fails.
#[unsafe(no_mangle)]
pub extern "C" fn harper_linter_create(dialect: *const c_char) -> *mut HarperLinter {
    let dialect_str = if dialect.is_null() {
        "american"
    } else {
        unsafe { CStr::from_ptr(dialect) }
            .to_str()
            .unwrap_or("american")
    };
    let dialect = match dialect_str.to_ascii_lowercase().as_str() {
        "canadian" => Dialect::Canadian,
        "australian" => Dialect::Australian,
        "british" => Dialect::British,
        "indian" => Dialect::Indian,
        _ => Dialect::American,
    };
    Box::into_raw(Box::new(HarperLinter {
        dialect,
        custom_words: Vec::new(),
        dictionary: None,
        group: None,
        dirty: true,
    }))
}

#[unsafe(no_mangle)]
pub extern "C" fn harper_linter_free(linter: *mut HarperLinter) {
    if !linter.is_null() {
        unsafe {
            drop(Box::from_raw(linter));
        }
    }
}

/// Adds a custom dictionary word. Safe to call with a null linter or word.
#[unsafe(no_mangle)]
pub extern "C" fn harper_linter_add_word(linter: *mut HarperLinter, word: *const c_char) {
    if linter.is_null() || word.is_null() {
        return;
    }
    let text = unsafe { CStr::from_ptr(word) }
        .to_string_lossy()
        .trim()
        .to_string();
    if text.is_empty() {
        return;
    }
    let linter = unsafe { &mut *linter };
    if !linter.custom_words.iter().any(|w| w == &text) {
        linter.custom_words.push(text);
        linter.dirty = true;
    }
}

/// Lints `text` (`byte_len` UTF-8 bytes) and returns a heap array of lints.
///
/// Returns `0` on success, `-1` for a null argument, `-2` for invalid UTF-8.
/// On success `*out_lints` and `*out_count` are always written (an empty result
/// is a null array with count 0).
#[unsafe(no_mangle)]
pub extern "C" fn harper_linter_lint(
    linter: *mut HarperLinter,
    text: *const c_char,
    byte_len: i32,
    out_lints: *mut *mut HarperLintC,
    out_count: *mut i32,
) -> i32 {
    if linter.is_null() || out_lints.is_null() || out_count.is_null() {
        return -1;
    }
    unsafe {
        *out_lints = std::ptr::null_mut();
        *out_count = 0;
    }
    let linter = unsafe { &mut *linter };
    let bytes = if text.is_null() || byte_len <= 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(text as *const u8, byte_len as usize) }
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return -2;
    };

    if linter.dirty || linter.group.is_none() {
        let dictionary = build_dictionary(&linter.custom_words, linter.dialect);
        linter.group = Some(LintGroup::new_curated(dictionary.clone(), linter.dialect));
        linter.dictionary = Some(dictionary);
        linter.dirty = false;
    }
    let group = linter.group.as_mut().expect("group was just built");
    let dictionary = linter.dictionary.as_ref().expect("dictionary was just built");

    let document = Document::new_plain_english(text, &**dictionary);
    let lints = group.lint(&document);

    let offsets = utf16_offsets(text);
    let mut result: Vec<HarperLintC> = Vec::with_capacity(lints.len());
    for lint in &lints {
        let start_idx = lint.span.start.min(offsets.len().saturating_sub(1));
        let end_idx = lint.span.end.min(offsets.len().saturating_sub(1));
        let start = offsets[start_idx];
        let end = offsets[end_idx];
        let kind_str = lint.lint_kind.to_string_key();
        let (suggestion_ptr, has_suggestion) = match lint.suggestions.first() {
            Some(Suggestion::ReplaceWith(chars)) => {
                (owned_c_string(&chars.iter().collect::<String>()), 1)
            }
            Some(Suggestion::InsertAfter(chars)) => {
                (owned_c_string(&chars.iter().collect::<String>()), 1)
            }
            Some(Suggestion::Remove) => (owned_c_string(""), 1),
            None => (std::ptr::null(), 0),
        };
        result.push(HarperLintC {
            start: start.min(i32::MAX as usize) as i32,
            length: end.saturating_sub(start).min(i32::MAX as usize) as i32,
            kind: owned_c_string(&kind_str),
            message: owned_c_string(&lint.message),
            suggestion: suggestion_ptr,
            has_suggestion,
        });
    }

    let count = result.len() as i32;
    let boxed: Box<[HarperLintC]> = result.into_boxed_slice();
    let ptr = Box::into_raw(boxed) as *mut HarperLintC;
    unsafe {
        *out_lints = ptr;
        *out_count = count;
    }
    0
}

/// Frees an array returned by [`harper_linter_lint`].
#[unsafe(no_mangle)]
pub extern "C" fn harper_lints_free(lints: *mut HarperLintC, count: i32) {
    if lints.is_null() || count <= 0 {
        return;
    }
    unsafe {
        let slice = std::slice::from_raw_parts_mut(lints, count as usize);
        for item in slice.iter() {
            for pointer in [item.kind, item.message, item.suggestion] {
                if !pointer.is_null() {
                    drop(CString::from_raw(pointer as *mut c_char));
                }
            }
        }
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
            lints,
            count as usize,
        )));
    }
}

/// Always `0` for the real backend. The Swift stub target returns `1`; the
/// adapter reports that state instead of pretending Harper is available.
#[unsafe(no_mangle)]
pub extern "C" fn harper_linter_is_stub() -> i32 {
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn lint(text: &str, words: &[&str]) -> Vec<(usize, usize, String, String, Option<String>)> {
        let linter = harper_linter_create(std::ptr::null());
        assert!(!linter.is_null());
        for word in words {
            let c = CString::new(*word).unwrap();
            harper_linter_add_word(linter, c.as_ptr());
        }
        let c_text = CString::new(text).unwrap();
        let mut out: *mut HarperLintC = std::ptr::null_mut();
        let mut count = 0;
        let status = harper_linter_lint(linter, c_text.as_ptr(), text.len() as i32, &mut out, &mut count);
        assert_eq!(status, 0);
        let mut lints = Vec::new();
        if !out.is_null() {
            let slice = unsafe { std::slice::from_raw_parts(out, count as usize) };
            for item in slice {
                let kind = unsafe { CStr::from_ptr(item.kind) }.to_string_lossy().to_string();
                let message = unsafe { CStr::from_ptr(item.message) }
                    .to_string_lossy()
                    .to_string();
                let suggestion = if item.has_suggestion == 1 && !item.suggestion.is_null() {
                    Some(
                        unsafe { CStr::from_ptr(item.suggestion) }
                            .to_string_lossy()
                            .to_string(),
                    )
                } else {
                    None
                };
                lints.push((item.start as usize, item.length as usize, kind, message, suggestion));
            }
        }
        harper_lints_free(out, count);
        harper_linter_free(linter);
        lints
    }

    #[test]
    fn offsets_are_utf16_after_emoji() {
        let text = "😀 teh cat";
        let lints = lint(text, &[]);
        let spelling = lints
            .iter()
            .find(|(_, _, kind, _, _)| kind == "Spelling")
            .expect("spelling lint for teh");
        // The emoji occupies two UTF-16 units, so "teh" starts at 3.
        assert_eq!(spelling.0, 3);
        assert_eq!(spelling.1, 3);
        assert_eq!(spelling.4.as_deref(), Some("the"));
    }

    #[test]
    fn offsets_are_utf16_for_cjk() {
        let text = "你好 teh cat";
        let lints = lint(text, &[]);
        let spelling = lints
            .iter()
            .find(|(_, _, kind, _, _)| kind == "Spelling")
            .expect("spelling lint for teh");
        // CJK scalars are one UTF-16 unit each: 2 + space = offset 3.
        assert_eq!(spelling.0, 3);
        assert_eq!(spelling.1, 3);
    }

    #[test]
    fn repeated_words_are_repetition() {
        let lints = lint("the the cat", &[]);
        assert!(lints.iter().any(|(_, _, kind, _, _)| kind == "Repetition"));
    }

    #[test]
    fn custom_words_suppress_spelling() {
        let lints = lint("superflow ships", &["superflow"]);
        assert!(
            !lints.iter().any(|(_, _, kind, _, _)| kind == "Spelling"),
            "unexpected lints: {lints:?}"
        );
    }

    #[test]
    fn invalid_utf8_is_rejected() {
        let linter = harper_linter_create(std::ptr::null());
        let bytes = [0xff_u8, 0xfe];
        let mut out: *mut HarperLintC = std::ptr::null_mut();
        let mut count = 0;
        let status = harper_linter_lint(
            linter,
            bytes.as_ptr() as *const c_char,
            bytes.len() as i32,
            &mut out,
            &mut count,
        );
        assert_eq!(status, -2);
        harper_linter_free(linter);
    }

    #[test]
    fn real_backend_is_not_a_stub() {
        assert_eq!(harper_linter_is_stub(), 0);
    }
}

