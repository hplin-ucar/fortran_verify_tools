module a_mod
  use shr_kind_mod, only: r8 => shr_kind_r8
  implicit none
  interface
     subroutine ext_sub(x)
       real :: x
     end subroutine ext_sub
  end interface
contains
  subroutine outer(n, x, y)
    integer, intent(in) :: n
    real(r8), intent(in)  :: x(:)
    real(r8), intent(out) :: y(:)   ! output
    integer :: i
    do i = 1, n
       y(i) = helper(x(i)) * 2.0_r8 + &
              1.0_r8
    end do
    call ext_sub(y(1))
  contains
    pure real(r8) function helper(v) result(w)
      real(r8), intent(in) :: v
      w = v ** 2
    end function helper
  end subroutine outer

  subroutine second(msg)
    character(len=*), intent(in) :: msg
    ! this has 'subroutine fake' in a string, and a ! inside it
    write(*,*) 'subroutine fake was called! '//msg
  end subroutine second
end module a_mod
