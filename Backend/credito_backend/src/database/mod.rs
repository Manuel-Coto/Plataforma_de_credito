pub mod connection;
pub mod init;

/// CouchDB devuelve `nil` cuando todavía no hay un cursor que pueda reenviarse.
/// Los cursores reales son opacos y se conservan sin alterar su contenido.
pub(crate) fn normalizar_bookmark(bookmark: String) -> String {
    if bookmark == "nil" {
        String::new()
    } else {
        bookmark
    }
}

#[cfg(test)]
mod bookmark_tests {
    use super::normalizar_bookmark;

    #[test]
    fn sentinel_nil_no_es_un_cursor_publico() {
        assert_eq!(normalizar_bookmark("nil".into()), "");
    }

    #[test]
    fn conserva_cursor_vacio_y_cursores_opacos() {
        for bookmark in ["", "cursor+opaco/nil=", "Nil", " nil "] {
            assert_eq!(normalizar_bookmark(bookmark.into()), bookmark);
        }
    }
}

#[cfg(test)]
mod tests;
