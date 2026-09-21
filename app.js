const firebaseConfig = {
  apiKey: "AIzaSyAwekJwvDBPi-k1WIr1GUpt1-lQ8yvOO9w",
  authDomain: "sikiro-f966b.firebaseapp.com",
  projectId: "sikiro-f966b",
  storageBucket: "sikiro-f966b.firebasestorage.app",
  messagingSenderId: "208531942537",
  appId: "1:208531942537:web:1c6b5cb2728ef3cbedaa58",
  measurementId: "G-W10N8DBYJ1"
};

firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();

let currentMode = 'register';
let selectedRole = 'Docente';

function switchMode(mode) {
  currentMode = mode;
  const title = document.getElementById('form-title');
  const btn = document.getElementById('btn-action');
  const roleGroup = document.getElementById('role-group');

  if (mode === 'register') {
    document.getElementById('tab-register').classList.add('active');
    document.getElementById('tab-login').classList.remove('active');
    title.textContent = "CREAR CUENTA";
    btn.textContent = "REGISTRARSE";
    roleGroup.classList.remove('hidden');
  } else {
    document.getElementById('tab-login').classList.add('active');
    document.getElementById('tab-register').classList.remove('active');
    title.textContent = "ACCESO SIKIRO";
    btn.textContent = "INGRESAR";
    roleGroup.classList.add('hidden');
  }
  document.getElementById('error-message').textContent = '';
}

function selectRole(role) {
  selectedRole = role;
  if (role === 'Docente') {
    document.getElementById('role-docente').classList.add('active');
    document.getElementById('role-estudiante').classList.remove('active');
  } else {
    document.getElementById('role-estudiante').classList.add('active');
    document.getElementById('role-docente').classList.remove('active');
  }
}

function togglePassword() {
  const pwd = document.getElementById('password');
  const eye = document.getElementById('eye-icon');
  if (pwd.type === 'password') {
    pwd.type = 'text';
    eye.innerHTML = `<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path><line x1="1" y1="1" x2="23" y2="23"></line>`;
  } else {
    pwd.type = 'password';
    eye.innerHTML = `<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle>`;
  }
}

function handleAuth(e) {
  e.preventDefault();
  const email = document.getElementById('email').value.trim();
  const pwd = document.getElementById('password').value;
  const err = document.getElementById('error-message');
  err.textContent = '';

  if (currentMode === 'login') {
    auth.signInWithEmailAndPassword(email, pwd).catch(() => {
      err.textContent = "Correo o contraseña incorrectos.";
    });
  } else {
    auth.createUserWithEmailAndPassword(email, pwd).catch((error) => {
      if (error.code === 'auth/weak-password') err.textContent = "La contraseña debe tener al menos 6 caracteres.";
      else if (error.code === 'auth/email-already-in-use') err.textContent = "Este correo electrónico ya está registrado.";
      else err.textContent = "No se pudo realizar el registro.";
    });
  }
}

auth.onAuthStateChanged((user) => {
  const authView = document.getElementById('auth-view');
  const teacherView = document.getElementById('teacher-view');
  const studentView = document.getElementById('student-view');
  const badge = document.getElementById('display-role');
  const btnLogout = document.getElementById('btn-logout');

  if (user) {
    authView.classList.add('hidden');
    btnLogout.classList.remove('hidden');

    let currentRole = localStorage.getItem('sikiro_role');
    if (!currentRole) {
      currentRole = selectedRole;
      localStorage.setItem('sikiro_role', currentRole);
    }

    badge.textContent = `🍎 Modo ${currentRole}`;

    if (currentRole === 'Docente') {
      teacherView.classList.remove('hidden');
      studentView.classList.add('hidden');
    } else {
      studentView.classList.remove('hidden');
      teacherView.classList.add('hidden');
    }
  } else {
    authView.classList.remove('hidden');
    teacherView.classList.add('hidden');
    studentView.classList.add('hidden');
    badge.textContent = 'No conectado';
    btnLogout.classList.add('hidden');
    localStorage.removeItem('sikiro_role');
  }
});

function logoutUser() {
  auth.signOut();
  localStorage.clear();
}

// Lógica Docente
let tTimer = null;
let tSeconds = 0;
let tPaused = false;
let activeCode = '';
let receivedQuestions = 0;

function generateCode() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

function startTeacherClass() {
  const sub = document.getElementById('t-subject').value.trim();
  const top = document.getElementById('t-topic').value.trim();

  if (!sub || !top) {
    alert('Por favor completa la asignatura y el tema.');
    return;
  }

  activeCode = generateCode();
  localStorage.setItem('sikiro_active_code', activeCode);
  localStorage.setItem('sikiro_active_topic', `${sub} - ${top}`);

  document.getElementById('t-live-subject').textContent = sub;
  document.getElementById('t-live-topic').textContent = top;
  document.getElementById('t-live-code').textContent = activeCode;

  document.getElementById('t-setup').classList.add('hidden');
  document.getElementById('t-live').classList.remove('hidden');

  tSeconds = 0;
  clearInterval(tTimer);
  tTimer = setInterval(() => {
    if (!tPaused) {
      tSeconds++;
      const h = Math.floor(tSeconds / 3600);
      const m = Math.floor((tSeconds % 3600) / 60);
      const s = tSeconds % 60;
      document.getElementById('t-timer').textContent = `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
      
      syncTeacherRealtime();
    }
  }, 1000);
}

function syncTeacherRealtime() {
  const savedStudents = parseInt(localStorage.getItem('sikiro_students') || '0');
  document.getElementById('t-students').textContent = `${savedStudents} ${savedStudents === 1 ? 'Alumno' : 'Alumnos'}`;

  const latestQ = localStorage.getItem('sikiro_last_question');
  if (latestQ && latestQ !== window.lastDisplayedQ) {
    window.lastDisplayedQ = latestQ;
    receivedQuestions++;
    document.getElementById('t-q-count').textContent = `${receivedQuestions} Recibidas`;

    const list = document.getElementById('t-questions-list');
    const emptyMsg = list.querySelector('p');
    if (emptyMsg) emptyMsg.remove();

    const div = document.createElement('div');
    div.className = 'q-item';
    div.innerHTML = `🔒 <em>Anónimo:</em> ${latestQ}`;
    list.prepend(div);
  }

  const currentRhythm = localStorage.getItem('sikiro_rhythm') || 'Adecuado';
  document.getElementById('t-rhythm-status').textContent = currentRhythm;
}

function toggleTeacherPause() {
  tPaused = !tPaused;
  const btn = document.getElementById('t-btn-pause');
  btn.textContent = tPaused ? '▶️ Reanudar Clase' : '⏸️ Pausar Clase';
}

function finishTeacherClass() {
  clearInterval(tTimer);
  document.getElementById('sum-sub').textContent = document.getElementById('t-live-subject').textContent;
  document.getElementById('sum-top').textContent = document.getElementById('t-live-topic').textContent;
  document.getElementById('sum-cod').textContent = activeCode;
  document.getElementById('sum-dur').textContent = document.getElementById('t-timer').textContent;
  document.getElementById('sum-stu').textContent = document.getElementById('t-students').textContent;

  document.getElementById('t-live').classList.add('hidden');
  document.getElementById('t-summary').classList.remove('hidden');
}

function resetTeacherDemo() {
  localStorage.clear();
  auth.signOut();
  document.getElementById('t-subject').value = '';
  document.getElementById('t-topic').value = '';
  document.getElementById('t-summary').classList.add('hidden');
  document.getElementById('t-setup').classList.remove('hidden');
}

// Lógica Estudiante
function joinStudentClass() {
  const codeInput = document.getElementById('s-input-code').value.trim().toUpperCase();
  if (!codeInput) {
    alert('Ingresa un código de clase válido.');
    return;
  }

  let currentStudents = parseInt(localStorage.getItem('sikiro_students') || '0');
  localStorage.setItem('sikiro_students', currentStudents + 1);

  const topicInfo = localStorage.getItem('sikiro_active_topic') || 'Clase Interactiva Sikiro';
  document.getElementById('s-class-title').textContent = `Clase: ${topicInfo}`;

  document.getElementById('s-join').classList.add('hidden');
  document.getElementById('s-active').classList.remove('hidden');
}

function sendAnonymousQuestion() {
  const text = document.getElementById('s-question-text').value.trim();
  if (!text) {
    alert('Escribe tu pregunta antes de enviar.');
    return;
  }

  localStorage.setItem('sikiro_last_question', text);
  alert('🔒 Tu pregunta ha sido enviada de forma anónima al profesor con éxito.');
  document.getElementById('s-question-text').value = '';
}

function setRhythm(rhythmValue, btnElement) {
  const parent = btnElement.parentElement;
  parent.querySelectorAll('.rhythm-btn').forEach(b => b.classList.remove('active'));
  btnElement.classList.add('active');

  localStorage.setItem('sikiro_rhythm', rhythmValue);
}

function leaveClass() {
  let currentStudents = parseInt(localStorage.getItem('sikiro_students') || '1');
  if (currentStudents > 0) localStorage.setItem('sikiro_students', currentStudents - 1);

  document.getElementById('s-active').classList.add('hidden');
  document.getElementById('s-join').classList.remove('hidden');
}