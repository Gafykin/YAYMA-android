//! Управление плагинами подмены аудио. Вся логика — в `crate::plugin_host`.

use crate::plugin_host::{self as plugins, USER_PLUGIN_ID};
use serde::{Deserialize, Serialize};

const MAX_PLUGIN_BYTES: usize = 8 * 1024 * 1024;

#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PluginDto {
    pub id: String,
    pub name: String,
    pub description: String,
    pub enabled: bool,
    pub source_url: Option<String>,
    pub tracks_count: u32,
}

/// Результат действия: `ok` + человекочитаемое сообщение для уведомления.
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PluginActionDto {
    pub ok: bool,
    pub message: String,
}

fn done(message: impl Into<String>) -> PluginActionDto {
    PluginActionDto {
        ok: true,
        message: message.into(),
    }
}

fn failed(message: impl Into<String>) -> PluginActionDto {
    PluginActionDto {
        ok: false,
        message: message.into(),
    }
}

async fn download_text(url: &str) -> Result<String, String> {
    if !plugins::is_http_url(url) {
        return Err("нужна ссылка вида http:// или https://".to_string());
    }
    let client = crate::util::tls::builder()
        .timeout(std::time::Duration::from_secs(20))
        .build()
        .map_err(|e| e.to_string())?;
    let response = client
        .get(url.trim())
        .send()
        .await
        .map_err(|e| format!("не удалось скачать: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("сервер ответил {}", response.status()));
    }
    let bytes = response.bytes().await.map_err(|e| e.to_string())?;
    if bytes.len() > MAX_PLUGIN_BYTES {
        return Err("файл слишком большой".to_string());
    }
    String::from_utf8(bytes.to_vec()).map_err(|_| "файл не в кодировке UTF-8".to_string())
}

fn install_text(text: &str, fallback_name: &str, source_url: Option<String>) -> PluginActionDto {
    let parsed = match plugins::parse_plugin(text) {
        Ok(parsed) => parsed,
        Err(e) => return failed(e),
    };
    let skipped = parsed.skipped;
    match plugins::install_parsed(parsed, fallback_name, source_url) {
        Ok(plugin) => {
            let mut message = format!(
                "Плагин «{}» установлен: {} треков",
                plugin.name,
                plugin.replacements.len()
            );
            if skipped > 0 {
                message.push_str(&format!(" (пропущено записей: {skipped})"));
            }
            done(message)
        }
        Err(e) => failed(format!("не удалось сохранить плагин: {e}")),
    }
}

fn name_from_url(url: &str) -> String {
    let path = url.split(['?', '#']).next().unwrap_or(url);
    let last = path.rsplit('/').find(|s| !s.is_empty()).unwrap_or("plugin");
    last.trim_end_matches(".json").to_string()
}

fn name_from_file(file_name: &str) -> String {
    let name = file_name.trim_end_matches(".json").trim();
    if name.is_empty() {
        "plugin".to_string()
    } else {
        name.to_string()
    }
}

pub async fn plugin_list() -> Vec<PluginDto> {
    plugins::list()
        .into_iter()
        // Служебный плагин ручных замен показываем только когда в нём что-то есть.
        .filter(|p| p.id != USER_PLUGIN_ID || !p.replacements.is_empty())
        .map(|p| PluginDto {
            tracks_count: p.replacements.len() as u32,
            id: p.id,
            name: p.name,
            description: p.description,
            enabled: p.enabled,
            source_url: p.source_url,
        })
        .collect()
}

pub async fn plugin_set_enabled(id: String, enabled: bool) -> PluginActionDto {
    if !plugins::is_valid_id(&id) {
        return failed("некорректный id плагина");
    }
    match plugins::set_enabled(&id, enabled) {
        Ok(()) => done(if enabled {
            "Плагин включён"
        } else {
            "Плагин выключен"
        }),
        Err(e) => failed(e),
    }
}

pub async fn plugin_remove(id: String) -> PluginActionDto {
    if !plugins::is_valid_id(&id) {
        return failed("некорректный id плагина");
    }
    match plugins::remove(&id) {
        Ok(()) => done("Плагин удалён"),
        Err(e) => failed(e),
    }
}

pub async fn plugin_install_from_url(url: String) -> PluginActionDto {
    let url = url.trim().to_string();
    match download_text(&url).await {
        Ok(text) => install_text(&text, &name_from_url(&url), Some(url)),
        Err(e) => failed(e),
    }
}

pub async fn plugin_install_from_json(json: String, file_name: String) -> PluginActionDto {
    install_text(&json, &name_from_file(&file_name), None)
}

/// Перекачивает плагин с адреса, с которого он был установлен.
pub async fn plugin_refresh(id: String) -> PluginActionDto {
    let Some(plugin) = plugins::list().into_iter().find(|p| p.id == id) else {
        return failed("плагин не найден");
    };
    let Some(url) = plugin.source_url.clone() else {
        return failed("у плагина нет адреса для обновления");
    };
    match download_text(&url).await {
        Ok(text) => {
            let mut result = install_text(&text, &plugin.name, Some(url));
            if result.ok {
                result.message = format!("Плагин «{}» обновлён", plugin.name);
            }
            result
        }
        Err(e) => failed(e),
    }
}

/// Текущая ручная замена аудио для трека (если есть).
pub async fn plugin_get_track_override(track_id: String) -> Option<String> {
    plugins::get_user_override(&track_id)
}

/// Ручная замена аудио трека. `url = None` или пустая строка — вернуть оригинал.
/// Действует со следующего запуска трека.
pub async fn plugin_set_track_override(track_id: String, url: Option<String>) -> PluginActionDto {
    let url = url.map(|u| u.trim().to_string()).filter(|u| !u.is_empty());
    if let Some(u) = &url {
        if !plugins::is_http_url(u) {
            return failed("нужна ссылка вида http:// или https:// на mp3-файл");
        }
    }
    let removing = url.is_none();
    match plugins::set_user_override(&track_id, url) {
        Ok(()) => done(if removing {
            "Оригинальное аудио возвращено"
        } else {
            "Замена сохранена — вступит в силу при следующем запуске трека"
        }),
        Err(e) => failed(e),
    }
}
