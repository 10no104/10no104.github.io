// 모든 네비게이션 버튼 선택
const buttons = document.querySelectorAll('.navBtn');

buttons.forEach(btn => {
  btn.addEventListener('click', () => {
    const targetId = btn.getAttribute('data-target');
    const targetEl = document.getElementById(targetId);
    targetEl.scrollIntoView({ behavior: 'smooth' });
  });
});
