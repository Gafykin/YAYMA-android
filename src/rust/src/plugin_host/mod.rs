//! Плагины: подмена аудиофайла трека (идея аддона FckCensor для PulseSync).
//!
//! Плагин — JSON-файл в `<каталог данных приложения>/plugins/`. Главное в нём —
//! список замен «id трека -> ссылка на mp3». Приложение само никаких списков
//! не поставляет: пользователь добавляет плагины сам (по ссылке или из файла).
//!
//! Поддерживаемые форматы плагина (при установке разбираются по форме JSON):
//!   1. манифест: `{ "name": "...", "description": "...", "replacements": { "123": "https://.../a.mp3" } }`
//!      (вместо `replacements` можно `tracks` / `map` / `mapping` / `overrides`);
//!   2. плоский словарь `{ "123": "https://.../a.mp3", ... }` (формат `trackId => mp3Url`);
//!   3. массив `[ { "id": "123", "url": "https://.../a.mp3" }, ... ]`.

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::sync::OnceLock;

/// Служебный плагин для ручных замен («Подменить аудио» в меню трека).
pub const USER_PLUGIN_ID: &str = "my-replacements";

const URL_KEYS: [&str; 6] = ["url", "mp3", "mp3Url", "mp3_url", "link", "src"];
const ID_KEYS: [&str; 3] = ["id", "track_id", "trackId"];
const MAP_KEYS: [&str; 5] = ["replacements", "tracks", "map", "mapping", "overrides"];

fn default_true() -> bool {
    true
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Plugin {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Откуда плагин скачан (нужно для кнопки «Обновить»).
    #[serde(default)]
    pub source_url: Option<String>,
    /// id трека -> ссылка на mp3.
    #[serde(default)]
    pub replacements: BTreeMap<String, String>,
}

#[derive(Default)]
struct Registry {
    loaded: bool,
    plugins: Vec<Plugin>,
    /// Сводный индекс по всем включённым плагинам: id трека -> ссылка.
    /// Ручные замены имеют приоритет над остальными плагинами.
    index: HashMap<String, String>,
}

impl Registry {
    fn rebuild_index(&mut self) {
        let mut index: HashMap<String, String> = HashMap::new();
        {
            let mut ordered: Vec<&Plugin> = self.plugins.iter().filter(|p| p.enabled).collect();
            ordered.sort_by_key(|p| p.id != USER_PLUGIN_ID);
            for plugin in ordered {
                for (id, url) in &plugin.replacements {
                    index.entry(id.clone()).or_insert_with(|| url.clone());
                }
            }
        }
        self.index = index;
    }
}

static REGISTRY: OnceLock<RwLock<Registry>> = OnceLock::new();

fn registry() -> &'static RwLock<Registry> {
    REGISTRY.get_or_init(|| RwLock::new(Registry::default()))
}

fn plugins_dir() -> Option<PathBuf> {
    crate::app::get_data_dir().map(|dir| dir.join("plugins"))
}

/// Id трека без суффикса альбома (`123:456` -> `123`).
fn base_id(id: &str) -> &str {
    id.split(':').next().unwrap_or(id).trim()
}

pub fn is_http_url(s: &str) -> bool {
    let s = s.trim();
    (s.starts_with("http://") || s.starts_with("https://")) && !s.contains(char::is_whitespace)
}

/// Id плагина используется в имени файла, поэтому допускаем только безопасные символы.
pub fn is_valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
}

pub fn slugify(s: &str) -> String {
    let mut out = String::new();
    let mut last_dash = false;
    for c in s.chars().flat_map(|c| c.to_lowercase()) {
        if c.is_ascii_alphanumeric() {
            out.push(c);
            last_dash = false;
        } else if !last_dash && !out.is_empty() {
            out.push('-');
            last_dash = true;
        }
    }
    let trimmed = out.trim_matches('-');
    if trimmed.is_empty() {
        "plugin".to_string()
    } else {
        trimmed.chars().take(48).collect()
    }
}

// ---------------------------------------------------------------- диск ----

fn ensure_loaded(reg: &mut Registry) {
    if reg.loaded {
        return;
    }
    // Каталог данных ещё не задан (до initialize_infrastructure) — попробуем позже.
    let Some(dir) = plugins_dir() else {
        return;
    };
    reg.loaded = true;
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return;
    };
    let mut plugins: Vec<Plugin> = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(&path) else {
            continue;
        };
        match serde_json::from_str::<Plugin>(&text) {
            Ok(plugin) if is_valid_id(&plugin.id) => plugins.push(plugin),
            Ok(_) => tracing::warn!(file = %path.display(), "plugin_invalid_id"),
            Err(e) => tracing::warn!(file = %path.display(), error = %e, "plugin_load_failed"),
        }
    }
    plugins.sort_by_key(|p| p.name.to_lowercase());
    reg.plugins = plugins;
    reg.rebuild_index();
}

fn write_plugin(plugin: &Plugin) -> Result<(), String> {
    let dir = plugins_dir().ok_or_else(|| "каталог данных приложения недоступен".to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let text = serde_json::to_string_pretty(plugin).map_err(|e| e.to_string())?;
    std::fs::write(dir.join(format!("{}.json", plugin.id)), text).map_err(|e| e.to_string())
}

fn delete_plugin_file(id: &str) {
    if let Some(dir) = plugins_dir() {
        let _ = std::fs::remove_file(dir.join(format!("{id}.json")));
    }
}

// --------------------------------------------------------- публичный API ----

/// Ссылка на замену аудио для трека (если какой-то включённый плагин её задаёт).
/// Вызывается при создании потока воспроизведения.
pub fn override_url(track_id: &str) -> Option<String> {
    {
        let reg = registry().read();
        if reg.loaded {
            return reg.index.get(base_id(track_id)).cloned();
        }
    }
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    reg.index.get(base_id(track_id)).cloned()
}

pub fn list() -> Vec<Plugin> {
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    reg.plugins.clone()
}

pub fn upsert(plugin: Plugin) -> Result<(), String> {
    write_plugin(&plugin)?;
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    if let Some(pos) = reg.plugins.iter().position(|p| p.id == plugin.id) {
        reg.plugins[pos] = plugin;
    } else {
        reg.plugins.push(plugin);
    }
    reg.plugins.sort_by_key(|p| p.name.to_lowercase());
    reg.rebuild_index();
    Ok(())
}

pub fn set_enabled(id: &str, enabled: bool) -> Result<(), String> {
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    let Some(pos) = reg.plugins.iter().position(|p| p.id == id) else {
        return Err("плагин не найден".to_string());
    };
    reg.plugins[pos].enabled = enabled;
    let snapshot = reg.plugins[pos].clone();
    reg.rebuild_index();
    drop(reg);
    write_plugin(&snapshot)
}

pub fn remove(id: &str) -> Result<(), String> {
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    reg.plugins.retain(|p| p.id != id);
    reg.rebuild_index();
    drop(reg);
    delete_plugin_file(id);
    Ok(())
}

pub fn get_user_override(track_id: &str) -> Option<String> {
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    reg.plugins
        .iter()
        .find(|p| p.id == USER_PLUGIN_ID)
        .and_then(|p| p.replacements.get(base_id(track_id)).cloned())
}

/// `Some(url)` — задать ручную замену, `None` — убрать.
pub fn set_user_override(track_id: &str, url: Option<String>) -> Result<(), String> {
    let key = base_id(track_id).to_string();
    if key.is_empty() {
        return Err("пустой id трека".to_string());
    }
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    let pos = match reg.plugins.iter().position(|p| p.id == USER_PLUGIN_ID) {
        Some(pos) => pos,
        None => {
            reg.plugins.push(Plugin {
                id: USER_PLUGIN_ID.to_string(),
                name: "Мои замены".to_string(),
                description: "Ручные замены из меню трека".to_string(),
                enabled: true,
                source_url: None,
                replacements: BTreeMap::new(),
            });
            reg.plugins.len() - 1
        }
    };
    match url {
        Some(url) => {
            reg.plugins[pos].replacements.insert(key, url);
        }
        None => {
            reg.plugins[pos].replacements.remove(&key);
        }
    }
    // Ручные замены всегда включены, иначе непонятно, почему «не работает».
    reg.plugins[pos].enabled = true;
    let snapshot = reg.plugins[pos].clone();
    reg.rebuild_index();
    drop(reg);
    write_plugin(&snapshot)
}

fn unique_id(base: &str) -> String {
    let mut reg = registry().write();
    ensure_loaded(&mut reg);
    let taken = |id: &str| id == USER_PLUGIN_ID || reg.plugins.iter().any(|p| p.id == id);
    let mut candidate = base.to_string();
    let mut n = 2;
    while taken(&candidate) {
        candidate = format!("{base}-{n}");
        n += 1;
    }
    candidate
}

// -------------------------------------------------------------- разбор ----

#[derive(Default)]
pub struct ParsedPlugin {
    pub id: Option<String>,
    pub name: Option<String>,
    pub description: Option<String>,
    pub source_url: Option<String>,
    pub replacements: BTreeMap<String, String>,
    /// Сколько записей пропущено (нет id или ссылка не http/https).
    pub skipped: usize,
}

fn pick_str(v: &Value, keys: &[&str]) -> Option<String> {
    for key in keys {
        match v.get(*key) {
            Some(Value::String(s)) => return Some(s.clone()),
            Some(Value::Number(n)) => return Some(n.to_string()),
            _ => {}
        }
    }
    None
}

fn add_pair(id: &str, url: &str, out: &mut BTreeMap<String, String>, skipped: &mut usize) {
    let key = base_id(id).to_string();
    if key.is_empty() || !is_http_url(url) {
        *skipped += 1;
        return;
    }
    out.insert(key, url.trim().to_string());
}

fn collect_mapping(v: &Value, out: &mut BTreeMap<String, String>, skipped: &mut usize) {
    match v {
        Value::Object(obj) => {
            for (id, val) in obj {
                let url = match val {
                    Value::String(s) => Some(s.clone()),
                    other => pick_str(other, &URL_KEYS),
                };
                match url {
                    Some(url) => add_pair(id, &url, out, skipped),
                    None => *skipped += 1,
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                let id = pick_str(item, &ID_KEYS);
                let url = pick_str(item, &URL_KEYS);
                match (id, url) {
                    (Some(id), Some(url)) => add_pair(&id, &url, out, skipped),
                    _ => *skipped += 1,
                }
            }
        }
        _ => {}
    }
}

pub fn parse_plugin(text: &str) -> Result<ParsedPlugin, String> {
    let value: Value = serde_json::from_str(text.trim_start_matches('\u{feff}'))
        .map_err(|e| format!("файл не является корректным JSON: {e}"))?;

    let mut parsed = ParsedPlugin::default();
    let mut map: BTreeMap<String, String> = BTreeMap::new();
    let mut skipped = 0usize;

    if value.is_object() {
        parsed.id = pick_str(&value, &["id"]);
        parsed.name = pick_str(&value, &["name", "title"]);
        parsed.description = pick_str(&value, &["description"]);
        parsed.source_url = pick_str(&value, &["source_url", "sourceUrl", "update_url"]);
        match MAP_KEYS.iter().find_map(|k| value.get(*k)) {
            Some(inner) => collect_mapping(inner, &mut map, &mut skipped),
            None => collect_mapping(&value, &mut map, &mut skipped),
        }
    } else {
        collect_mapping(&value, &mut map, &mut skipped);
    }

    if map.is_empty() {
        return Err("в файле нет ни одной пары «id трека → ссылка на mp3»".to_string());
    }
    parsed.replacements = map;
    parsed.skipped = skipped;
    Ok(parsed)
}

/// Создаёт (или обновляет) плагин из разобранных данных и сохраняет его.
/// Если плагин с таким источником/id уже есть — обновляется он, включённость сохраняется.
pub fn install_parsed(
    parsed: ParsedPlugin,
    fallback_name: &str,
    source_url: Option<String>,
) -> Result<Plugin, String> {
    let source = source_url.or_else(|| parsed.source_url.clone());
    let existing = list().into_iter().find(|p| {
        p.id != USER_PLUGIN_ID
            && ((source.is_some() && p.source_url == source)
                || parsed.id.as_deref().map(slugify).as_deref() == Some(p.id.as_str()))
    });

    let name = parsed
        .name
        .clone()
        .filter(|n| !n.trim().is_empty())
        .or_else(|| existing.as_ref().map(|p| p.name.clone()))
        .unwrap_or_else(|| fallback_name.to_string());

    let (id, enabled) = match &existing {
        Some(p) => (p.id.clone(), p.enabled),
        None => {
            let base = slugify(parsed.id.as_deref().unwrap_or(name.as_str()));
            (unique_id(&base), true)
        }
    };

    let plugin = Plugin {
        id,
        name,
        description: parsed.description.unwrap_or_default(),
        enabled,
        source_url: source,
        replacements: parsed.replacements,
    };
    upsert(plugin.clone())?;
    Ok(plugin)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_flat_map() {
        let p = parse_plugin(r#"{"123":"https://x.test/a.mp3","bad":"ftp://x","456:789":"http://y.test/b.mp3"}"#)
            .unwrap();
        assert_eq!(p.replacements.len(), 2);
        assert_eq!(p.replacements.get("456").map(String::as_str), Some("http://y.test/b.mp3"));
        assert_eq!(p.skipped, 1);
    }

    #[test]
    fn parses_manifest_and_array() {
        let p = parse_plugin(r#"{"name":"N","tracks":[{"id":1,"mp3":"https://x.test/1.mp3"}]}"#).unwrap();
        assert_eq!(p.name.as_deref(), Some("N"));
        assert_eq!(p.replacements.get("1").map(String::as_str), Some("https://x.test/1.mp3"));
    }

    #[test]
    fn rejects_empty() {
        assert!(parse_plugin("{}").is_err());
        assert!(parse_plugin("not json").is_err());
    }

    #[test]
    fn slug_is_safe() {
        assert_eq!(slugify("Мой плагин!"), "plugin");
        assert_eq!(slugify("Fck Censor / v2"), "fck-censor-v2");
        assert!(is_valid_id(&slugify("../../etc")));
    }
}
