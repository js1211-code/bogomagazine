package com.bogomagazine.modules.layout.api;

/**
 * 조판 알고리즘의 순수 함수 경계. DB와 스토리지에 접근하지 않는다.
 * 같은 input + algorithmVersion + seed는 같은 output이어야 한다 (stats.elapsedMs 제외).
 *
 * @throws ComposeException 입력이 잘못됐거나(input_invalid) 내용이 없을 때(no_content)
 */
public interface LayoutEngine {
    ComposeOutput compose(ComposeInput input);
}
