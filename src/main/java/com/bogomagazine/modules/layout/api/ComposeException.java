package com.bogomagazine.modules.layout.api;

/**
 * 조판 실패. 메시지는 "코드: 설명"으로 시작하므로 fail_compose_job의 p_error에 그대로 넘긴다
 * (docs/composition-engine-api.md 9장).
 */
public class ComposeException extends RuntimeException {
    public static final String INPUT_INVALID = "input_invalid";
    public static final String NO_CONTENT = "no_content";

    private final String code;

    public ComposeException(String code, String detail) {
        super(code + ": " + detail);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
