/**
 * Formatage des messages traduits (Custom Labels) : remplace {0}, {1}… par les arguments, dans l'ordre.
 *
 * Volontairement plus simple que String.format : String.format suit les règles de MessageFormat, où une
 * apostrophe ouvre une zone littérale (« n'est » perdrait son apostrophe et les marqueurs qui suivent
 * ne seraient plus remplacés). Les libellés français en sont pleins.
 */
public inherited sharing class AR_I18n {
    public static String format(String template, List<Object> args) {
        if (template == null) {
            return '';
        }
        String result = template;
        if (args == null) {
            return result;
        }
        for (Integer i = 0; i < args.size(); i++) {
            Object value = args[i];
            result = result.replace('{' + i + '}', value == null ? '' : String.valueOf(value));
        }
        return result;
    }
}