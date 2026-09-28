module b_mod
  use ccpp_kinds, only: kind_phys
  implicit none
contains
subroutine outer_run(n, x, y)
      INTEGER, intent(in) :: n
      real(kind_phys), intent(in) :: x(:)
      real(kind_phys), intent(out) :: y(:)
      integer :: i
      do i = 1, n
         y(i) = helper(x(i)) * 2.0_kind_phys + 1.0_kind_phys
      end do
      call ext_sub(y(1))
contains
      pure real(kind_phys) function helper(v) &
           result(w)
        real(kind_phys), intent(in) :: v
        w = v ** 2
      end function helper
end subroutine outer_run

  subroutine second(msg)
    character(len=*), intent(in) :: msg
    write(*,*) 'subroutine fake was called! '//trim(msg)
  end subroutine second
end module b_mod
