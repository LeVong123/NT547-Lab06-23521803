# NT547 - LAB 06 - BÁO CÁO (TỰ ĐIỀN)

**MSSV:** 23521803  | **Họ tên:** Lê Vọng | **Lớp:** NT547.R11.ANTT
**Session code tự sinh:** SC-93224C | **Tên contract:** StakingPool_1803
**Solidity / Slither:** 0.8.24 / 0.11.6 | **Ngày hoàn thành:** 2026-11-20
**URL GitHub repository:** [chưa tạo]

## 1. Static scan (2,0 điểm)

- Lệnh raw: `python tools/scan.py --mode raw --tag before`
- Số lượng finding raw từ `evidence/before_raw/summary.json`:
  - High: 4; Medium: 1; Low: 1; Informational: 5; Optimization: 0 (tổng 11 finding)
- Chạy configured: `python tools/scan.py --mode configured --tag before`
- So sánh raw/configured: configured còn 5 finding (High 4, Medium 1); loại 1 Low và 5 Informational. Không có High/Medium biến mất khi chỉ đổi config.
- 3 detector **khác tên**: `weak-prng`, `encode-packed-collision`, `tx-origin`.

| ID finding | Detector | Impact | Confidence | Source (file:dòng) | Luồng dữ liệu: đầu vào -> thao tác -> tác hại |
|---|---|---|---|---|---|
| F01 | `weak-prng` | High | Medium | `AuditTarget.sol:settle`, dòng 56-63 (biểu thức 58) | Người chơi gọi `enter()` và gửi 0.01 ETH -> `settle()` chọn chỉ số bằng `block.timestamp % participants.length` -> người tạo block có thể ảnh hưởng kết quả chọn người thắng và khoản thanh toán. |
| F02 | `encode-packed-collision` | High | High | `AuditTarget.sol:redeemCode`, dòng 83-88 (biểu thức 84) | Người gọi cung cấp hai chuỗi `campaign`, `code` -> `abi.encodePacked` nối hai chuỗi động không có ranh giới rồi băm -> hai cặp khác nhau có thể dùng chung khóa `claimedKeys`, khiến một cặp bị coi là đã dùng sau khi cặp kia claim; mapping vẫn chặn dùng lại cùng khóa. |
| F03 | `tx-origin` | Medium | Medium | `AuditTarget.sol:updateOwner`, dòng 90-94 (điều kiện 91) | Chủ sở hữu bị dụ gọi hợp đồng trung gian do kẻ tấn công kiểm soát -> `tx.origin` vẫn là chủ sở hữu nên kiểm tra qua, dù `msg.sender` là hợp đồng trung gian -> hàm đổi `owner` sang địa chỉ do kẻ tấn công chọn. |

## 2. Triage và sửa lỗi (2,5 điểm)

Đọc toàn bộ AuditTarget.sol: nhận diện **4 mẫu lỗi thật + 2 đoạn cần đánh giá ngữ cảnh**,
kể cả khi Slither không hiển thị đủ 6 cảnh báo. Với mẫu không có detector,
ghi “Manual review / Not reported”, KHÔNG sửa slither.json hoặc tạo finding giả.

| Detector + vị trí | TP / FP / Chưa kết luận | Bằng chứng kiểm soát/khả năng khai thác | Biện pháp (Fix / Accept có lý do) | Sau sửa |
|---|---|---|---|---|
| `weak-prng` — `settle`, dòng 58 | TP | Hàm chỉOwner chọn người thắng và chuyển toàn bộ ETH bằng chỉ số lấy từ `block.timestamp % participants.length`; người tạo block có thể ảnh hưởng timestamp, còn owner có thể trì hoãn thời điểm settle. | Fix: thay nguồn lựa chọn dựa trên timestamp bằng cơ chế randomness phù hợp (ví dụ commit-reveal có kiểm soát); không suppression vì kết quả quyết định người nhận tiền. | Chưa áp dụng; chờ baseline CI RED rồi sửa và scan after. |
| `encode-packed-collision` — `redeemCode`, dòng 84 | TP | Hai chuỗi động được nối không phân cách trước khi băm; cặp chuỗi khác nhau có thể tạo cùng ID, khiến khóa dùng một lần của cặp này chặn cặp kia. Không kết luận rằng có thể dùng lại cùng một ID vì `claimedKeys[id]` vẫn chặn lần hai. | Fix: dùng `abi.encode(campaign, code)` để mã hóa ranh giới hai giá trị trước khi băm. | Chưa áp dụng; chờ baseline CI RED rồi sửa và scan after. |
| `reentrancy-eth` — `redeemSafe`, dòng 71 | Accepted / contextual | `redeemSafe` và `saveSafe` đều dùng `exclusive`; modifier đặt `mutex = true` trước thân hàm nên callback không thể gọi lại các entrypoint này để rút lặp `held`. Đây làm giảm rủi ro của đường reentrancy ETH mà detector báo High. `updateOwner` là đường riêng có lỗi `tx.origin`, được triage riêng. | Giữ mutex và harden theo Checks-Effects-Interactions: đặt `held[msg.sender] = 0` trước external call; nếu call thất bại, revert sẽ khôi phục state. | Chưa áp dụng; chờ baseline CI RED rồi sửa và scan after. |
| `suicidal` — `destroyPool`, dòng 47-49 | TP | Hàm không có `onlyOwner`; bất kỳ địa chỉ nào cũng có thể gọi và chuyển số ETH còn lại của contract cho chính caller. Sau Cancun/EIP-6780, trong trường hợp thông thường không được khẳng định rằng code/storage bị xóa; việc chuyển ETH vẫn là tác hại. | Fix: bỏ chức năng nếu không cần; nếu cần đóng pool thì giới hạn `onlyOwner` và mô tả rõ tác dụng. | Chưa áp dụng; chờ baseline CI RED rồi sửa và scan after. |
| `tx-origin` — `updateOwner`, dòng 91 | TP | Nếu owner bị dụ gọi contract trung gian, `tx.origin` vẫn là owner trong khi `msg.sender` là contract đó; contract trung gian có thể gọi `updateOwner(attacker)` để chiếm quyền quản trị. | Fix: kiểm tra `msg.sender == owner` thay cho `tx.origin == owner`. | Chưa áp dụng; chờ baseline CI RED rồi sửa và scan after. |
| `timestamp` — `vestStep`, dòng 77 | Accepted / contextual | Đây là kiểm tra cooldown một ngày trong hàm `onlyOwner`, không dùng timestamp để chọn ngẫu nhiên hay cấp quyền; sai lệch timestamp ở ranh giới có thể ảnh hưởng thời điểm gọi nhưng không bỏ qua quyền owner. | Accept có lý do: giữ cooldown theo thời gian; nêu rõ đây không phải nguồn randomness và chỉ chấp nhận sai lệch thời điểm nhỏ theo ngữ cảnh chain. | Chưa scan after; dự kiến có thể còn detector Low trong raw. |

- Kịch bản khai thác TP: owner bị dụ gọi contract trung gian do kẻ tấn công kiểm soát -> contract trung gian gọi `updateOwner(attacker)` khi `tx.origin == owner` -> state `owner` đổi sang địa chỉ attacker -> attacker chiếm quyền quản trị.
- Finding severity cao nhưng risk thực tế thấp hơn: `reentrancy-eth` báo High tại `redeemSafe`, nhưng modifier `exclusive` khóa cả `redeemSafe` và `saveSafe` trong lúc external call; callback không thể rút lặp số dư qua các entrypoint này. Lỗi `tx.origin` ở `updateOwner` được đánh giá riêng. Sẽ áp dụng Checks-Effects-Interactions như hardening và kiểm tra lại sau scan.
- Bằng chứng `git diff` và scan after: chờ baseline CI RED trước khi sửa; bổ sung diff, kết quả hai chế độ scan và giải thích detector còn lại sau khi hoàn tất.
- Suppression: hiện chưa dùng `slither-disable-next-line`; không suppression finding khai thác được và không loại High/Medium khỏi cấu hình.

## 3. Kiến trúc / Inheritance (1,5 điểm)

- Lệnh printer đã chạy: ...
- Ảnh `evidence/architecture/inheritance.png` (hoặc .dot, nếu Graphviz chưa có): ...
- Access control nằm ở ...; logic số dư nằm ở ...; contract triển khai nằm ở ...
- Giải thích 3–5 câu điểm audit cần bắt đầu: ...

## 4. Red -> Green CI (2,5 điểm)

| Phase | Commit (full/short SHA) | Run URL | Kết quả | Detector khiến RED / lý do GREEN |
|---|---|---|---|---|
| Baseline vulnerable | | | RED | |
| Patched | | | GREEN | |

- So sánh local `--fail-none` (thu thập findings) với CI `fail-on: medium`: ...
- `exclude_low/informational` thay đổi kết quả hiển thị ra sao: ...

## 5. Mutation RED -> GREEN (1,5 điểm)

- Mutation một dòng: `require(msg.sender == owner, "not owner")` -> `require(tx.origin == owner, "not owner")` trong `modifier onlyOwner`.
- Detector kỳ vọng: `tx-origin` (mức Medium); xác nhận của em từ CI: ...

| Phase | Commit SHA | Run URL | Kết quả |
|---|---|---|---|
| Mutation | | | RED |
| Revert mutation | | | GREEN |

- Giải thích sự thay đổi về nguồn định danh/authorization: ...

## 6. Bằng chứng, tự kiểm

- [ ] `AuditTarget.sol`, `lab_identity.json`
- [ ] `evidence/before_raw/` và `evidence/before_configured/`
- [ ] `evidence/after_raw/` và `evidence/after_configured/`
- [ ] `evidence/architecture/`
- [ ] 04 URL Actions run RED/GREEN/RED/GREEN + 04 commit SHA
- [ ] Link repo và ảnh màn hình có terminal / URL / commit SHA; không cắt mất ngữ cảnh
- [ ] Các finding được triage, không chép lại mô tả detector thay cho suy luận
- [ ] Tuyệt đối không có seed phrase, private key, credentials

**Nhận xét cuối cùng (5–7 câu):** ...
